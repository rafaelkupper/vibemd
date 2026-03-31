import AppKit
import QuartzCore
import VibeMDCore

@MainActor
enum WindowChromeSuppression {
    static func suppress(in window: NSWindow) {
        guard let frameView = window.contentView?.superview else {
            return
        }

        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = ReaderTheme.backgroundColor.cgColor

        for subview in frameView.subviews {
            let className = NSStringFromClass(type(of: subview))
            applyFlatBackgroundIfNeeded(
                to: subview,
                named: className,
                superviewName: NSStringFromClass(type(of: frameView))
            )
            if shouldHideView(named: className, topLevel: true) {
                subview.isHidden = true
            }
        }

        for descendant in recursiveSubviews(in: frameView) {
            let className = NSStringFromClass(type(of: descendant))
            let superviewName = descendant.superview.map { NSStringFromClass(type(of: $0)) }
            applyFlatBackgroundIfNeeded(to: descendant, named: className, superviewName: superviewName)
            if shouldHideView(named: className, topLevel: false) {
                descendant.isHidden = true
            }
        }
    }

    static func shouldHideView(named className: String, topLevel: Bool) -> Bool {
        if topLevel && className == "NSVisualEffectView" {
            return true
        }

        if className == "_NSTitlebarDecorationView" || className == "NSTitlebarBackgroundView" {
            return true
        }

        return className.contains("ScrollPocket")
    }

    static func shouldStyleView(named className: String, superviewName: String?) -> Bool {
        if className == "NSTitlebarContainerView" || className == "NSTitlebarView" {
            return true
        }

        return className == "NSView" && superviewName == "NSTitlebarView"
    }

    private static func applyFlatBackgroundIfNeeded(to view: NSView, named className: String, superviewName: String?) {
        guard shouldStyleView(named: className, superviewName: superviewName) else {
            return
        }

        view.wantsLayer = true
        view.layer?.backgroundColor = ReaderTheme.backgroundColor.cgColor
    }

    private static func recursiveSubviews(in rootView: NSView) -> [NSView] {
        rootView.subviews + rootView.subviews.flatMap(recursiveSubviews(in:))
    }
}

@MainActor
final class DocumentWindowController: NSWindowController {
    static let initialContentSize = NSSize(width: 1040, height: 760)
    static let cascadeOffset: CGFloat = 28

    private let chromeViewController: DocumentChromeViewController
    private let statisticsAccessoryController: DocumentStatisticsAccessoryViewController

    var onSelectSidebarDocument: ((URL) -> Void)? {
        get { chromeViewController.onSelectSidebarDocument }
        set { chromeViewController.onSelectSidebarDocument = newValue }
    }

    var onSelectOutlineItem: ((String) -> Void)? {
        get { chromeViewController.onSelectOutlineItem }
        set { chromeViewController.onSelectOutlineItem = newValue }
    }

    init(
        contentViewController: NSViewController,
        cascadeFrom sourceWindow: NSWindow? = nil,
        statisticPreferenceStore: DocumentStatisticPreferenceStore = .shared
    ) {
        let initialContentSize = Self.initialContentSize
        self.chromeViewController = DocumentChromeViewController(contentViewController: contentViewController)
        self.statisticsAccessoryController = DocumentStatisticsAccessoryViewController(
            preferenceStore: statisticPreferenceStore
        )
        contentViewController.loadViewIfNeeded()
        contentViewController.view.frame = NSRect(origin: .zero, size: initialContentSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = chromeViewController
        window.setContentSize(initialContentSize)
        window.minSize = NSSize(width: 520, height: 360)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.backgroundColor = ReaderTheme.backgroundColor
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        let visibleFrame = sourceWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        if let visibleFrame {
            window.setFrame(
                Self.initialFrame(
                    contentSize: initialContentSize,
                    visibleFrame: visibleFrame,
                    cascadeFrom: sourceWindow?.frame
                ),
                display: false
            )
        } else {
            window.center()
        }

        super.init(window: window)
        statisticsAccessoryController.onToggleSidebar = { [weak self] in
            self?.toggleSidebar()
        }
        window.addTitlebarAccessoryViewController(statisticsAccessoryController)
        chromeViewController.installCenteredTitleIfNeeded(in: window)
        suppressSystemTitlebarBackground(in: window)
        shouldCascadeWindows = true
        setDisplayedTitle("")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var hostedContentViewController: NSViewController {
        chromeViewController.contentViewController
    }

    var displayedStatisticTextForTesting: String? {
        statisticsAccessoryController.displayedTextForTesting
    }

    var displayedWindowTitleForTesting: String {
        chromeViewController.displayedTitleForTesting
    }

    var titleViewHostClassNameForTesting: String? {
        chromeViewController.titleViewHostClassNameForTesting
    }

    var isSidebarVisibleForTesting: Bool {
        chromeViewController.isSidebarVisible
    }

    var sidebarModeForTesting: DocumentSidebarMode {
        chromeViewController.sidebarMode
    }

    var sidebarDocumentTitlesForTesting: [String] {
        chromeViewController.sidebarDocumentTitlesForTesting
    }

    var outlineTitlesForTesting: [String] {
        chromeViewController.outlineTitlesForTesting
    }

    var sidebarButtonIsActiveForTesting: Bool {
        statisticsAccessoryController.sidebarButtonIsActiveForTesting
    }

    var isSidebarAttachedForTesting: Bool {
        chromeViewController.isSidebarAttachedForTesting
    }

    var activeOutlineAnchorIDForTesting: String? {
        chromeViewController.activeOutlineAnchorIDForTesting
    }

    var sidebarWidthForTesting: CGFloat {
        chromeViewController.sidebarWidthForTesting
    }

    var sidebarAlphaForTesting: CGFloat {
        chromeViewController.sidebarAlphaForTesting
    }

    var isContentAlignedWithSidebarForTesting: Bool {
        chromeViewController.isContentAlignedWithSidebarForTesting
    }

    static var sidebarAnimationDurationForTesting: TimeInterval {
        DocumentChromeViewController.sidebarAnimationDuration
    }

    func triggerSidebarToggleForTesting() {
        statisticsAccessoryController.triggerSidebarToggleForTesting()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else {
            return
        }

        suppressSystemTitlebarBackground(in: window)
        chromeViewController.installCenteredTitleIfNeeded(in: window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else {
                return
            }

            self.chromeViewController.installCenteredTitleIfNeeded(in: window)
            self.suppressSystemTitlebarBackground(in: window)
        }
    }

    func prepareSidebarForAnimatedOpenForTesting() {
        chromeViewController.prepareSidebarForAnimatedOpen()
    }

    func setReducedMotionForTesting(_ value: Bool?) {
        chromeViewController.reducedMotionOverride = value
    }

    func setSidebarModeForTesting(_ mode: DocumentSidebarMode) {
        chromeViewController.setSidebarMode(mode)
    }

    func triggerSidebarDocumentSelectionForTesting(_ url: URL) {
        chromeViewController.triggerSidebarDocumentSelectionForTesting(url)
    }

    func triggerOutlineSelectionForTesting(_ anchorID: String) {
        chromeViewController.triggerOutlineSelectionForTesting(anchorID)
    }

    func apply(documentStatistics: DocumentStatistics?) {
        statisticsAccessoryController.apply(statistics: documentStatistics)
    }

    func setDisplayedTitle(_ title: String) {
        window?.title = title
        chromeViewController.setDisplayedTitle(title)
    }

    func apply(sidebarEntries: [DocumentSidebarEntry], outlineItems: [DocumentOutlineItem]) {
        chromeViewController.apply(sidebarEntries: sidebarEntries, outlineItems: outlineItems)
    }

    func setActiveOutlineAnchorID(_ anchorID: String?) {
        chromeViewController.setActiveOutlineAnchorID(anchorID)
    }

    func toggleSidebar() {
        chromeViewController.toggleSidebar()
        statisticsAccessoryController.setSidebarActive(chromeViewController.isSidebarVisible)
        if let window {
            suppressSystemTitlebarBackground(in: window)
            chromeViewController.installCenteredTitleIfNeeded(in: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else {
                    return
                }

                self.chromeViewController.installCenteredTitleIfNeeded(in: window)
                self.suppressSystemTitlebarBackground(in: window)
            }
        }
    }

    private func suppressSystemTitlebarBackground(in window: NSWindow) {
        WindowChromeSuppression.suppress(in: window)
    }

    static func initialFrame(
        contentSize: NSSize,
        visibleFrame: NSRect,
        cascadeFrom sourceFrame: NSRect?
    ) -> NSRect {
        let unclampedOrigin: NSPoint
        if let sourceFrame {
            unclampedOrigin = NSPoint(
                x: sourceFrame.minX + cascadeOffset,
                y: sourceFrame.minY - cascadeOffset
            )
        } else {
            unclampedOrigin = NSPoint(
                x: visibleFrame.midX - (contentSize.width / 2),
                y: visibleFrame.midY - (contentSize.height / 2)
            )
        }

        let clampedOrigin = clampedOrigin(
            unclampedOrigin,
            contentSize: contentSize,
            visibleFrame: visibleFrame
        )

        return NSRect(origin: clampedOrigin, size: contentSize)
    }

    private static func clampedOrigin(
        _ origin: NSPoint,
        contentSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - contentSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - contentSize.height)

        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }
}

@MainActor
private final class DocumentChromeViewController: NSViewController {
    fileprivate static let sidebarAnimationDuration: TimeInterval = 0.26
    private static let titlebarLeadingInset: CGFloat = 88
    private static let titlebarTrailingInset: CGFloat = 154

    private struct WindowSizeLock {
        let frame: NSRect
        let minimumSize: NSSize
        let maximumSize: NSSize
        let minimumContentSize: NSSize
        let maximumContentSize: NSSize
    }

    let contentViewController: NSViewController
    private let hostedView: NSView
    private let sidebarViewController = DocumentSidebarViewController()
    private let sidebarContainerView = NSView()
    private let sidebarRevealView = NSView()
    private let titlebarBackgroundView = PassthroughTitlebarView()
    private let centeredTitleView = CenteredWindowTitleView()
    private var centeredTitleConstraints: [NSLayoutConstraint] = []
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var sidebarRevealWidthConstraint: NSLayoutConstraint?
    private var sidebarAttachmentConstraints: [NSLayoutConstraint] = []
    private var hostedLeadingWithoutSidebarConstraint: NSLayoutConstraint?
    private var hostedLeadingWithSidebarConstraint: NSLayoutConstraint?
    private var hostedTransitionLeadingConstraint: NSLayoutConstraint?
    private var transitionWindowSizeLock: WindowSizeLock?
    fileprivate var reducedMotionOverride: Bool?

    var onSelectSidebarDocument: ((URL) -> Void)? {
        get { sidebarViewController.onSelectDocument }
        set { sidebarViewController.onSelectDocument = newValue }
    }

    var onSelectOutlineItem: ((String) -> Void)? {
        get { sidebarViewController.onSelectOutlineItem }
        set { sidebarViewController.onSelectOutlineItem = newValue }
    }

    init(contentViewController: NSViewController) {
        self.contentViewController = contentViewController
        self.hostedView = contentViewController.view
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var isSidebarVisible: Bool {
        !(sidebarContainerView.isHidden)
    }

    var sidebarMode: DocumentSidebarMode {
        sidebarViewController.mode
    }

    var sidebarDocumentTitlesForTesting: [String] {
        sidebarViewController.documentTitlesForTesting
    }

    var outlineTitlesForTesting: [String] {
        sidebarViewController.outlineTitlesForTesting
    }

    var activeOutlineAnchorIDForTesting: String? {
        sidebarViewController.activeOutlineAnchorIDForTesting
    }

    var displayedTitleForTesting: String {
        centeredTitleView.title
    }

    var titleViewHostClassNameForTesting: String? {
        centeredTitleView.superview.map { NSStringFromClass(type(of: $0)) }
    }

    var sidebarWidthForTesting: CGFloat {
        sidebarRevealWidthConstraint?.constant ?? 0
    }

    var sidebarAlphaForTesting: CGFloat {
        sidebarContainerView.alphaValue
    }

    var isSidebarAttachedForTesting: Bool {
        sidebarContainerView.superview === view
    }

    var isContentAlignedWithSidebarForTesting: Bool {
        hostedLeadingWithSidebarConstraint?.isActive == true
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: DocumentWindowController.initialContentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = ReaderTheme.backgroundColor.cgColor

        sidebarContainerView.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainerView.wantsLayer = true
        sidebarContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        sidebarContainerView.layer?.masksToBounds = true
        sidebarContainerView.isHidden = true

        addChild(sidebarViewController)
        let sidebarView = sidebarViewController.view
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarRevealView.translatesAutoresizingMaskIntoConstraints = false
        sidebarRevealView.wantsLayer = true
        sidebarRevealView.layer?.backgroundColor = ReaderTheme.sidebarBackgroundColor.cgColor
        sidebarRevealView.layer?.masksToBounds = true
        sidebarContainerView.addSubview(sidebarRevealView)
        sidebarRevealView.addSubview(sidebarView)

        addChild(contentViewController)
        hostedView.translatesAutoresizingMaskIntoConstraints = false

        titlebarBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        titlebarBackgroundView.wantsLayer = true
        titlebarBackgroundView.layer?.backgroundColor = ReaderTheme.backgroundColor.cgColor

        view.addSubview(hostedView)
        view.addSubview(titlebarBackgroundView)

        sidebarWidthConstraint = sidebarContainerView.widthAnchor.constraint(equalToConstant: DocumentSidebarViewController.sidebarWidth)
        sidebarRevealWidthConstraint = sidebarRevealView.widthAnchor.constraint(equalToConstant: 0)
        hostedLeadingWithoutSidebarConstraint = hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        hostedLeadingWithSidebarConstraint = hostedView.leadingAnchor.constraint(equalTo: sidebarContainerView.trailingAnchor)
        sidebarAttachmentConstraints = [
            sidebarContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sidebarContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidthConstraint!,
        ]

        NSLayoutConstraint.activate([
            sidebarRevealView.leadingAnchor.constraint(equalTo: sidebarContainerView.leadingAnchor),
            sidebarRevealView.topAnchor.constraint(equalTo: sidebarContainerView.topAnchor),
            sidebarRevealView.bottomAnchor.constraint(equalTo: sidebarContainerView.bottomAnchor),
            sidebarRevealWidthConstraint!,

            sidebarView.leadingAnchor.constraint(equalTo: sidebarRevealView.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: sidebarRevealView.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: sidebarRevealView.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalTo: sidebarContainerView.widthAnchor),

            hostedLeadingWithoutSidebarConstraint!,
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            titlebarBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titlebarBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titlebarBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            titlebarBackgroundView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
    }

    func toggleSidebar() {
        setSidebarVisible(!isSidebarVisible)
    }

    func apply(sidebarEntries: [DocumentSidebarEntry], outlineItems: [DocumentOutlineItem]) {
        sidebarViewController.apply(sidebarEntries: sidebarEntries, outlineItems: outlineItems)
    }

    func setActiveOutlineAnchorID(_ anchorID: String?) {
        sidebarViewController.setActiveOutlineAnchorID(anchorID)
    }

    func setSidebarMode(_ mode: DocumentSidebarMode) {
        sidebarViewController.setMode(mode)
    }

    func triggerSidebarDocumentSelectionForTesting(_ url: URL) {
        sidebarViewController.triggerDocumentSelectionForTesting(url)
    }

    func triggerOutlineSelectionForTesting(_ anchorID: String) {
        sidebarViewController.triggerOutlineSelectionForTesting(anchorID)
    }

    func setDisplayedTitle(_ title: String) {
        centeredTitleView.title = title
    }

    func installCenteredTitleIfNeeded(in window: NSWindow) {
        let hostView = titlebarHostView(in: window) ?? view
        guard centeredTitleView.superview !== hostView else {
            return
        }

        NSLayoutConstraint.deactivate(centeredTitleConstraints)
        centeredTitleConstraints.removeAll()
        centeredTitleView.removeFromSuperview()
        centeredTitleView.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(centeredTitleView)

        if hostView === view {
            centeredTitleConstraints = [
                centeredTitleView.topAnchor.constraint(equalTo: view.topAnchor),
                centeredTitleView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                centeredTitleView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                centeredTitleView.leadingAnchor.constraint(
                    greaterThanOrEqualTo: view.leadingAnchor,
                    constant: Self.titlebarLeadingInset
                ),
                centeredTitleView.trailingAnchor.constraint(
                    lessThanOrEqualTo: view.trailingAnchor,
                    constant: -Self.titlebarTrailingInset
                ),
            ]
        } else {
            centeredTitleConstraints = [
                centeredTitleView.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
                centeredTitleView.centerYAnchor.constraint(equalTo: hostView.centerYAnchor),
                centeredTitleView.leadingAnchor.constraint(
                    greaterThanOrEqualTo: hostView.leadingAnchor,
                    constant: Self.titlebarLeadingInset
                ),
                centeredTitleView.trailingAnchor.constraint(
                    lessThanOrEqualTo: hostView.trailingAnchor,
                    constant: -Self.titlebarTrailingInset
                ),
            ]
        }

        NSLayoutConstraint.activate(centeredTitleConstraints)
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        let shouldReduceMotion = reducedMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if shouldReduceMotion {
            applySidebarVisibility(isVisible)
            sidebarContainerView.alphaValue = isVisible ? 1 : 0
            view.layoutSubtreeIfNeeded()
            return
        }

        let startLeading = isSidebarVisible ? DocumentSidebarViewController.sidebarWidth : 0

        if isVisible {
            prepareSidebarForAnimatedOpen()
        } else {
            prepareSidebarForAnimatedClose()
        }

        let endLeading = isVisible ? DocumentSidebarViewController.sidebarWidth : 0
        beginContentTransition(startLeading: startLeading, endLeading: endLeading)
        beginWindowSizeLockIfNeeded()
        view.layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.sidebarAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            hostedTransitionLeadingConstraint?.animator().constant = isVisible ? DocumentSidebarViewController.sidebarWidth : 0
            sidebarRevealWidthConstraint?.animator().constant = isVisible ? DocumentSidebarViewController.sidebarWidth : 0
            sidebarContainerView.animator().alphaValue = isVisible ? 1 : 0
            view.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.finalizeAnimatedSidebarTransition(isVisible: isVisible)
                self.endWindowSizeLockIfNeeded()
                self.view.layoutSubtreeIfNeeded()
            }
        }
    }

    fileprivate func prepareSidebarForAnimatedOpen() {
        attachSidebarIfNeeded()
        alignContentWithoutSidebar()
        sidebarContainerView.isHidden = false
        sidebarWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
        sidebarRevealWidthConstraint?.constant = 0
        sidebarContainerView.alphaValue = 0
    }

    private func prepareSidebarForAnimatedClose() {
        attachSidebarIfNeeded()
        alignContentWithSidebar()
        sidebarContainerView.isHidden = false
        sidebarWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
        sidebarRevealWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
        sidebarContainerView.alphaValue = 1
    }

    private func finalizeAnimatedSidebarTransition(isVisible: Bool) {
        if isVisible {
            finishContentTransition(activateSidebarAlignedConstraint: true)
            alignContentWithSidebar()
            sidebarContainerView.isHidden = false
            sidebarWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
            sidebarRevealWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
            sidebarContainerView.alphaValue = 1
        } else {
            finishContentTransition(activateSidebarAlignedConstraint: false)
            applySidebarVisibility(false)
            sidebarContainerView.alphaValue = 1
        }
    }

    private func applySidebarVisibility(_ isVisible: Bool) {
        if isVisible {
            attachSidebarIfNeeded()
            alignContentWithSidebar()
            sidebarContainerView.isHidden = false
            sidebarWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
            sidebarRevealWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
            sidebarContainerView.alphaValue = 1
        } else {
            alignContentWithoutSidebar()
            sidebarWidthConstraint?.constant = DocumentSidebarViewController.sidebarWidth
            sidebarRevealWidthConstraint?.constant = 0
            sidebarContainerView.isHidden = true
            detachSidebarIfNeeded()
        }
    }

    private func beginContentTransition(startLeading: CGFloat, endLeading: CGFloat) {
        hostedLeadingWithoutSidebarConstraint?.isActive = false
        hostedLeadingWithSidebarConstraint?.isActive = false

        if hostedTransitionLeadingConstraint == nil {
            hostedTransitionLeadingConstraint = hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        }
        hostedTransitionLeadingConstraint?.constant = startLeading
        hostedTransitionLeadingConstraint?.isActive = true

        view.layoutSubtreeIfNeeded()
    }

    private func finishContentTransition(activateSidebarAlignedConstraint: Bool) {
        hostedTransitionLeadingConstraint?.isActive = false
        hostedTransitionLeadingConstraint = nil

        if activateSidebarAlignedConstraint {
            alignContentWithSidebar()
        } else {
            alignContentWithoutSidebar()
        }
    }

    private func attachSidebarIfNeeded() {
        guard sidebarContainerView.superview !== view else {
            return
        }

        view.addSubview(sidebarContainerView, positioned: .above, relativeTo: hostedView)
        NSLayoutConstraint.activate(sidebarAttachmentConstraints)
    }

    private func alignContentWithSidebar() {
        hostedLeadingWithoutSidebarConstraint?.isActive = false
        hostedLeadingWithSidebarConstraint?.isActive = true
    }

    private func alignContentWithoutSidebar() {
        hostedLeadingWithSidebarConstraint?.isActive = false
        hostedLeadingWithoutSidebarConstraint?.isActive = true
    }

    private func detachSidebarIfNeeded() {
        guard sidebarContainerView.superview === view else {
            return
        }

        NSLayoutConstraint.deactivate(sidebarAttachmentConstraints)
        sidebarContainerView.removeFromSuperview()
    }

    private func titlebarHostView(in window: NSWindow) -> NSView? {
        guard let frameView = window.contentView?.superview else {
            return nil
        }

        return ([frameView] + recursiveSubviews(in: frameView)).first {
            NSStringFromClass(type(of: $0)) == "NSTitlebarView"
        }
    }

    private func recursiveSubviews(in rootView: NSView) -> [NSView] {
        rootView.subviews + rootView.subviews.flatMap(recursiveSubviews(in:))
    }

    private func beginWindowSizeLockIfNeeded() {
        guard transitionWindowSizeLock == nil, let window = view.window else {
            return
        }

        let contentSize = window.contentRect(forFrameRect: window.frame).size
        transitionWindowSizeLock = WindowSizeLock(
            frame: window.frame,
            minimumSize: window.minSize,
            maximumSize: window.maxSize,
            minimumContentSize: window.contentMinSize,
            maximumContentSize: window.contentMaxSize
        )
        let lockedSize = window.frame.size
        window.minSize = lockedSize
        window.maxSize = lockedSize
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
    }

    private func endWindowSizeLockIfNeeded() {
        guard let lock = transitionWindowSizeLock, let window = view.window else {
            return
        }

        transitionWindowSizeLock = nil
        window.minSize = lock.minimumSize
        window.maxSize = lock.maximumSize
        window.contentMinSize = lock.minimumContentSize
        window.contentMaxSize = lock.maximumContentSize
        if window.frame.size != lock.frame.size {
            window.setFrame(lock.frame, display: false)
        }
    }
}

@MainActor
private final class CenteredWindowTitleView: PassthroughTitlebarView {
    private let label = NSTextField(labelWithString: "")

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = ReaderTheme.sidebarPrimaryTextColor.withAlphaComponent(0.72)

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private class PassthroughTitlebarView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
