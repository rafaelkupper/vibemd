import AppKit
import VibeMDCore

@MainActor
final class DocumentStatisticsAccessoryViewController: NSTitlebarAccessoryViewController {
    private static let trailingInset: CGFloat = 14
    private static let minimumContainerHeight: CGFloat = 28
    private static let controlSpacing: CGFloat = 6

    private let preferenceStore: DocumentStatisticPreferenceStore
    private let notificationCenter: NotificationCenter
    private let containerView = NSView()
    private let stackView = NSStackView()
    private let pillView = DocumentStatisticsPillView()
    private let sidebarButton = TitlebarAccessoryIconButtonView(symbolName: "sidebar.left")
    private var statistics: DocumentStatistics?

    var onToggleSidebar: (() -> Void)? {
        get { sidebarButton.onActivate }
        set { sidebarButton.onActivate = newValue }
    }

    init(
        preferenceStore: DocumentStatisticPreferenceStore = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.preferenceStore = preferenceStore
        self.notificationCenter = notificationCenter
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
        fullScreenMinHeight = DocumentStatisticsPillView.defaultHeight
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    override func loadView() {
        containerView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = Self.controlSpacing
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        pillView.onActivate = { [weak self] in
            self?.showMetricMenu()
        }
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.setContentHuggingPriority(.required, for: .horizontal)
        pillView.setContentCompressionResistancePriority(.required, for: .horizontal)

        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarButton.setContentHuggingPriority(.required, for: .horizontal)
        sidebarButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        stackView.addArrangedSubview(pillView)
        stackView.addArrangedSubview(sidebarButton)
        containerView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Self.trailingInset),
            stackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
        ])

        view = containerView

        notificationCenter.addObserver(
            self,
            selector: #selector(handleStatisticKindChange),
            name: .documentStatisticKindDidChange,
            object: nil
        )

        updateDisplay()
    }

    func apply(statistics: DocumentStatistics?) {
        self.statistics = statistics
        updateDisplay()
    }

    func setSidebarActive(_ isActive: Bool) {
        sidebarButton.isActive = isActive
    }

    var displayedTextForTesting: String? {
        guard !pillView.isHidden else {
            return nil
        }

        return pillView.displayText
    }

    var sidebarButtonIsActiveForTesting: Bool {
        sidebarButton.isActive
    }

    var preferredWidthForTesting: CGFloat {
        preferredContentSize.width
    }

    func triggerSidebarToggleForTesting() {
        sidebarButton.onActivate?()
    }

    @objc
    func selectKind(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let kind = DocumentStatisticKind(rawValue: rawValue)
        else {
            return
        }

        preferenceStore.selectedKind = kind
    }

    @objc
    private func handleStatisticKindChange() {
        updateDisplay()
    }

    private func updateDisplay() {
        if let statistics {
            pillView.displayText = statistics.displayText(for: preferenceStore.selectedKind)
            pillView.isHidden = false
        } else {
            pillView.isHidden = true
        }

        let clusterSize = NSSize(width: clusterWidth(), height: clusterHeight())
        let containerSize = NSSize(
            width: clusterSize.width + Self.trailingInset,
            height: titlebarContainerHeight()
        )
        preferredContentSize = containerSize
        view.frame = NSRect(origin: .zero, size: containerSize)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.superview?.needsLayout = true
        view.superview?.layoutSubtreeIfNeeded()
    }

    private func clusterWidth() -> CGFloat {
        let visibleViews = stackView.arrangedSubviews.filter { !$0.isHidden }
        guard !visibleViews.isEmpty else {
            return 0
        }

        let widths = visibleViews.map { view in
            let intrinsic = view.intrinsicContentSize.width
            if intrinsic > 0 {
                return intrinsic
            }
            return view.fittingSize.width
        }

        return widths.reduce(0, +) + (Self.controlSpacing * CGFloat(max(visibleViews.count - 1, 0)))
    }

    private func clusterHeight() -> CGFloat {
        stackView.arrangedSubviews
            .filter { !$0.isHidden }
            .map { view in
                let intrinsic = view.intrinsicContentSize.height
                if intrinsic > 0 {
                    return intrinsic
                }
                return view.fittingSize.height
            }
            .max() ?? DocumentStatisticsPillView.defaultHeight
    }

    private func titlebarContainerHeight() -> CGFloat {
        guard let window = view.window else {
            return Self.minimumContainerHeight
        }

        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        return max(Self.minimumContainerHeight, titlebarHeight)
    }

    private func showMetricMenu() {
        let menu = NSMenu()
        let selectedKind = preferenceStore.selectedKind

        for kind in DocumentStatisticKind.allCases {
            let item = NSMenuItem(
                title: statistics?.displayText(for: kind) ?? kind.title,
                action: #selector(selectKind(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = kind == selectedKind ? .on : .off
            item.representedObject = kind.rawValue
            menu.addItem(item)
        }

        let anchor = NSPoint(x: pillView.bounds.maxX - 8, y: pillView.bounds.minY - 6)
        menu.popUp(positioning: nil, at: anchor, in: pillView)
    }
}

@MainActor
private final class DocumentStatisticsPillView: NSView {
    static let defaultHeight: CGFloat = 20
    private static let minimumWidth: CGFloat = 84
    private static let restingBackgroundAlpha: CGFloat = 0.045
    private static let hoverBackgroundAlpha: CGFloat = 0.08
    private static let hoverBorderAlpha: CGFloat = 0.14

    private let label = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            guard oldValue != isHovering else {
                return
            }

            updateAppearance()
        }
    }

    var onActivate: (() -> Void)?

    var displayText: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1

        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = NSColor(white: 0.86, alpha: 0.98)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        imageView.contentTintColor = NSColor(white: 0.82, alpha: 0.9)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [label, imageView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.defaultHeight),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        let imageSize = imageView.intrinsicContentSize
        return NSSize(
            width: max(Self.minimumWidth, labelSize.width + imageSize.width + 19),
            height: Self.defaultHeight
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(
            isHovering ? Self.hoverBackgroundAlpha : Self.restingBackgroundAlpha
        ).cgColor
        layer?.borderColor = isHovering
            ? NSColor.white.withAlphaComponent(Self.hoverBorderAlpha).cgColor
            : NSColor.clear.cgColor
    }
}

@MainActor
private final class TitlebarAccessoryIconButtonView: NSView {
    static let defaultSize = NSSize(width: 20, height: 20)

    private static let restingBackgroundAlpha: CGFloat = 0.03
    private static let hoverBackgroundAlpha: CGFloat = 0.07
    private static let activeBackgroundAlpha: CGFloat = 0.12
    private static let hoverBorderAlpha: CGFloat = 0.12

    private let imageView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            guard oldValue != isHovering else {
                return
            }

            updateAppearance()
        }
    }

    var isActive = false {
        didSet {
            guard oldValue != isActive else {
                return
            }

            updateAppearance()
        }
    }

    var onActivate: (() -> Void)?

    init(symbolName: String) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        imageView.contentTintColor = NSColor(white: 0.82, alpha: 0.92)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: Self.defaultSize.width),
            heightAnchor.constraint(equalToConstant: Self.defaultSize.height),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        Self.defaultSize
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    private func updateAppearance() {
        let backgroundAlpha: CGFloat
        if isActive {
            backgroundAlpha = Self.activeBackgroundAlpha
        } else if isHovering {
            backgroundAlpha = Self.hoverBackgroundAlpha
        } else {
            backgroundAlpha = Self.restingBackgroundAlpha
        }

        layer?.backgroundColor = NSColor.white.withAlphaComponent(backgroundAlpha).cgColor
        layer?.borderColor = (isHovering || isActive)
            ? NSColor.white.withAlphaComponent(Self.hoverBorderAlpha).cgColor
            : NSColor.clear.cgColor
    }
}
