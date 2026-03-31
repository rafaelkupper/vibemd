import AppKit
import VibeMDCore

enum OutlineSidebarMetrics {
    static let fontSize: CGFloat = 12.5
    static let rowVerticalInset: CGFloat = 4
    static let levelOneLeadingInset: CGFloat = 16
    static let indentationStep: CGFloat = 16

    static func leadingInset(for level: Int) -> CGFloat {
        levelOneLeadingInset + CGFloat(max(level - 1, 0)) * indentationStep
    }

    static func rowSpacing(after currentLevel: Int, nextLevel: Int?) -> CGFloat {
        guard let nextLevel else {
            return 0
        }

        if nextLevel > currentLevel {
            return 1
        }

        if nextLevel == 1 {
            return currentLevel == 1 ? 7 : 9
        }

        return 2
    }

    static func fontWeight(for level: Int, isSelected: Bool) -> NSFont.Weight {
        if isSelected || level == 1 {
            return .semibold
        }

        return .regular
    }

    static func textColor(for level: Int, isSelected: Bool, isHovering: Bool) -> NSColor {
        if isSelected {
            return ReaderTheme.sidebarPrimaryTextColor
        }

        if isHovering {
            return ReaderTheme.sidebarPrimaryTextColor.withAlphaComponent(level == 1 ? 0.92 : 0.82)
        }

        if level == 1 {
            return ReaderTheme.sidebarPrimaryTextColor.withAlphaComponent(0.88)
        }

        return ReaderTheme.sidebarSecondaryTextColor.withAlphaComponent(level <= 3 ? 0.9 : 0.82)
    }
}

@MainActor
enum DocumentSidebarMode: Int {
    case documents
    case outline

    var title: String {
        switch self {
        case .documents:
            "DOCUMENTS"
        case .outline:
            "OUTLINE"
        }
    }
}

@MainActor
final class DocumentSidebarViewController: NSViewController {
    static let sidebarWidth: CGFloat = 270

    private let modeToggleView = SidebarModeToggleView()
    private let titleLabel = NSTextField(labelWithString: DocumentSidebarMode.documents.title)
    private let scrollView = NSScrollView()
    private let contentStackView = NSStackView()

    private var sidebarEntries: [DocumentSidebarEntry] = []
    private var outlineItems: [DocumentOutlineItem] = []
    private var activeOutlineAnchorID: String?

    var onSelectDocument: ((URL) -> Void)?
    var onSelectOutlineItem: ((String) -> Void)?

    private(set) var mode: DocumentSidebarMode = .documents

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: 760))
        view.wantsLayer = true
        view.layer?.backgroundColor = ReaderTheme.sidebarBackgroundColor.cgColor

        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false

        modeToggleView.translatesAutoresizingMaskIntoConstraints = false
        modeToggleView.onSelectMode = { [weak self] mode in
            self?.setMode(mode)
        }
        modeToggleView.setMode(.documents)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = ReaderTheme.sidebarSecondaryTextColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(modeToggleView)
        headerView.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true

        contentStackView.orientation = .vertical
        contentStackView.alignment = .width
        contentStackView.distribution = .fill
        contentStackView.spacing = 0
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 18, right: 0)
        contentStackView.setHuggingPriority(.required, for: .vertical)
        contentStackView.setContentCompressionResistancePriority(.required, for: .vertical)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStackView)
        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
        ])
        scrollView.documentView = documentView
        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: clipView.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
            documentView.bottomAnchor.constraint(greaterThanOrEqualTo: contentStackView.bottomAnchor),
        ])

        view.addSubview(headerView)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 76),

            modeToggleView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            modeToggleView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 12),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        rebuildRows()
    }

    func apply(sidebarEntries: [DocumentSidebarEntry], outlineItems: [DocumentOutlineItem]) {
        self.sidebarEntries = sidebarEntries
        self.outlineItems = outlineItems
        rebuildRows()
    }

    func setMode(_ mode: DocumentSidebarMode) {
        guard self.mode != mode else {
            return
        }

        self.mode = mode
        modeToggleView.setMode(mode)
        titleLabel.stringValue = mode.title
        rebuildRows()
    }

    func setActiveOutlineAnchorID(_ anchorID: String?) {
        guard activeOutlineAnchorID != anchorID else {
            return
        }

        activeOutlineAnchorID = anchorID
        guard mode == .outline else {
            return
        }

        rebuildRows()
    }

    var documentTitlesForTesting: [String] {
        sidebarEntries.map(\.displayTitle)
    }

    var outlineTitlesForTesting: [String] {
        outlineItems.map(\.title)
    }

    var activeOutlineAnchorIDForTesting: String? {
        activeOutlineAnchorID
    }

    var arrangedRowFramesForTesting: [NSRect] {
        view.layoutSubtreeIfNeeded()
        return contentStackView.arrangedSubviews.map(\.frame)
    }

    var outlineLabelMinXPositionsForTesting: [CGFloat] {
        view.layoutSubtreeIfNeeded()
        return contentStackView.arrangedSubviews.compactMap { row in
            (row as? SidebarOutlineRowView)?.labelMinXForTesting
        }
    }

    var outlineLeadingInsetsForTesting: [CGFloat] {
        contentStackView.arrangedSubviews.compactMap { row in
            (row as? SidebarOutlineRowView)?.leadingInsetForTesting
        }
    }

    func triggerDocumentSelectionForTesting(_ url: URL) {
        onSelectDocument?(url)
    }

    func triggerOutlineSelectionForTesting(_ anchorID: String) {
        onSelectOutlineItem?(anchorID)
    }

    private func rebuildRows() {
        contentStackView.arrangedSubviews.forEach { subview in
            contentStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        switch mode {
        case .documents:
            buildDocumentRows()
        case .outline:
            buildOutlineRows()
        }
    }

    private func buildDocumentRows() {
        for entry in sidebarEntries {
            let row = SidebarDocumentRowView(entry: entry)
            row.onActivate = { [weak self] in
                guard entry.isAvailable else {
                    return
                }
                self?.onSelectDocument?(entry.fileURL)
            }
            contentStackView.addArrangedSubview(row)
            prepareRow(row)
        }
    }

    private func buildOutlineRows() {
        for (index, item) in outlineItems.enumerated() {
            let row = SidebarOutlineRowView(item: item, isActive: item.anchorID == activeOutlineAnchorID)
            row.onActivate = { [weak self] in
                self?.setActiveOutlineAnchorID(item.anchorID)
                self?.onSelectOutlineItem?(item.anchorID)
            }
            contentStackView.addArrangedSubview(row)
            prepareRow(row)
            let nextLevel = index + 1 < outlineItems.count ? outlineItems[index + 1].level : nil
            contentStackView.setCustomSpacing(
                OutlineSidebarMetrics.rowSpacing(after: item.level, nextLevel: nextLevel),
                after: row
            )
        }
    }

    private func prepareRow(_ row: NSView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
    }
}

@MainActor
private class SidebarSelectableRowView: NSView {
    static let cornerRadius: CGFloat = 7

    var onActivate: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    fileprivate var isHovering = false {
        didSet {
            guard oldValue != isHovering else {
                return
            }
            updateAppearance()
        }
    }

    var isSelected = false {
        didSet {
            guard oldValue != isSelected else {
                return
            }
            updateAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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

    func updateAppearance() {
        let backgroundColor: NSColor
        if isSelected {
            backgroundColor = ReaderTheme.sidebarSelectionColor
        } else if isHovering {
            backgroundColor = ReaderTheme.sidebarHoverColor
        } else {
            backgroundColor = .clear
        }
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

@MainActor
private final class SidebarDocumentRowView: SidebarSelectableRowView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")

    init(entry: DocumentSidebarEntry) {
        super.init(frame: .zero)

        isSelected = entry.isCurrent

        titleLabel.stringValue = entry.displayTitle
        titleLabel.font = .systemFont(ofSize: 13, weight: entry.isCurrent ? .semibold : .medium)
        titleLabel.textColor = entry.isAvailable ? ReaderTheme.sidebarPrimaryTextColor : ReaderTheme.sidebarSecondaryTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.stringValue = entry.previewText
        previewLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        previewLabel.textColor = entry.isAvailable
            ? ReaderTheme.sidebarSecondaryTextColor
            : ReaderTheme.sidebarSecondaryTextColor.withAlphaComponent(0.6)
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, previewLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class SidebarOutlineRowView: SidebarSelectableRowView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let itemLevel: Int
    private let rowLeadingInset: CGFloat

    init(item: DocumentOutlineItem, isActive: Bool) {
        self.itemLevel = item.level
        self.rowLeadingInset = OutlineSidebarMetrics.leadingInset(for: item.level)
        super.init(frame: .zero)

        self.isSelected = isActive
        titleLabel.stringValue = item.title
        titleLabel.alignment = .left
        titleLabel.font = .systemFont(
            ofSize: OutlineSidebarMetrics.fontSize,
            weight: OutlineSidebarMetrics.fontWeight(for: item.level, isSelected: isActive)
        )
        titleLabel.textColor = OutlineSidebarMetrics.textColor(for: item.level, isSelected: isActive, isHovering: false)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.wraps = false
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: rowLeadingInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: OutlineSidebarMetrics.rowVerticalInset),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -OutlineSidebarMetrics.rowVerticalInset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }

    var leadingInsetForTesting: CGFloat {
        rowLeadingInset
    }

    var labelMinXForTesting: CGFloat {
        titleLabel.frame.minX
    }

    override func updateAppearance() {
        layer?.backgroundColor = NSColor.clear.cgColor
        titleLabel.font = .systemFont(
            ofSize: OutlineSidebarMetrics.fontSize,
            weight: OutlineSidebarMetrics.fontWeight(for: itemLevel, isSelected: isSelected)
        )
        titleLabel.textColor = OutlineSidebarMetrics.textColor(
            for: itemLevel,
            isSelected: isSelected,
            isHovering: isHovering
        )
    }
}

@MainActor
private final class SidebarModeToggleView: NSView {
    private let containerStackView = NSStackView()
    private let documentsButton = SidebarModeButton(title: "Docs")
    private let outlineButton = SidebarModeButton(title: "Outline")

    var onSelectMode: ((DocumentSidebarMode) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = ReaderTheme.sidebarChromeFillColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = ReaderTheme.sidebarChromeBorderColor.cgColor

        containerStackView.orientation = .horizontal
        containerStackView.alignment = .centerY
        containerStackView.spacing = 4
        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        documentsButton.onActivate = { [weak self] in
            self?.onSelectMode?(.documents)
        }
        outlineButton.onActivate = { [weak self] in
            self?.onSelectMode?(.outline)
        }

        containerStackView.addArrangedSubview(documentsButton)
        containerStackView.addArrangedSubview(outlineButton)
        addSubview(containerStackView)

        NSLayoutConstraint.activate([
            containerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            containerStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            containerStackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setMode(_ mode: DocumentSidebarMode) {
        documentsButton.isSelected = mode == .documents
        outlineButton.isSelected = mode == .outline
    }
}

@MainActor
private final class SidebarModeButton: NSView {
    private let label = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            guard oldValue != isHovering else {
                return
            }
            updateAppearance()
        }
    }

    var isSelected = false {
        didSet {
            guard oldValue != isSelected else {
                return
            }
            updateAppearance()
        }
    }

    var onActivate: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        label.stringValue = title
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
        if isSelected {
            layer?.backgroundColor = ReaderTheme.sidebarChromeSelectedFillColor.cgColor
            label.textColor = ReaderTheme.sidebarPrimaryTextColor
        } else if isHovering {
            layer?.backgroundColor = ReaderTheme.sidebarChromeHoverFillColor.cgColor
            label.textColor = ReaderTheme.sidebarPrimaryTextColor.withAlphaComponent(0.92)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            label.textColor = ReaderTheme.sidebarSecondaryTextColor
        }
    }
}
