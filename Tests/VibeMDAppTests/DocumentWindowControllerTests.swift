import AppKit
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

@MainActor
final class DocumentWindowControllerTests: XCTestCase {
    func testWindowUsesUnifiedTitlebarChromeAndWrapsContentController() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = DocumentStatisticPreferenceStore(defaults: defaults)
        let contentViewController = NSViewController()
        let windowController = DocumentWindowController(
            contentViewController: contentViewController,
            statisticPreferenceStore: store
        )
        defer { windowController.close() }

        let window = try XCTUnwrap(windowController.window)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(
            window.backgroundColor.usingColorSpace(.deviceRGB),
            ReaderTheme.backgroundColor.usingColorSpace(.deviceRGB)
        )
        XCTAssertEqual(window.titlebarAccessoryViewControllers.count, 1)
        XCTAssertTrue(windowController.hostedContentViewController === contentViewController)
        XCTAssertFalse(window.contentViewController === contentViewController)
    }

    func testWindowUsesCenteredCustomDocumentTitle() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        windowController.setDisplayedTitle("RenderingShowcase.md")

        XCTAssertEqual(windowController.window?.title, "RenderingShowcase.md")
        XCTAssertEqual(windowController.displayedWindowTitleForTesting, "RenderingShowcase.md")
    }

    func testCenteredTitleInstallsIntoActualTitlebarHost() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        windowController.showWindow(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(windowController.titleViewHostClassNameForTesting, "NSTitlebarView")
    }

    func testWindowSuppressesSystemTitlebarBackgroundViews() throws {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        let frameView = try XCTUnwrap(windowController.window?.contentView?.superview)
        let frameVisualEffectViews = frameView.subviews.compactMap { $0 as? NSVisualEffectView }
        let descendants = recursiveSubviews(in: frameView)
        let titlebarBackgroundViews = descendants.filter {
            let className = NSStringFromClass(type(of: $0))
            return className == "_NSTitlebarDecorationView" || className == "NSTitlebarBackgroundView"
        }

        XCTAssertFalse(frameVisualEffectViews.contains(where: { !$0.isHidden }))
        XCTAssertFalse(titlebarBackgroundViews.contains(where: { !$0.isHidden }))
    }

    func testChromeSuppressionRecognizesScrollPocketAndTitlebarArtifacts() {
        XCTAssertTrue(WindowChromeSuppression.shouldHideView(named: "NSVisualEffectView", topLevel: true))
        XCTAssertTrue(WindowChromeSuppression.shouldHideView(named: "_NSTitlebarDecorationView", topLevel: false))
        XCTAssertTrue(WindowChromeSuppression.shouldHideView(named: "NSTitlebarBackgroundView", topLevel: false))
        XCTAssertTrue(WindowChromeSuppression.shouldHideView(named: "NSScrollPocket", topLevel: false))
        XCTAssertTrue(WindowChromeSuppression.shouldStyleView(named: "NSTitlebarContainerView", superviewName: "NSThemeFrame"))
        XCTAssertTrue(WindowChromeSuppression.shouldStyleView(named: "NSTitlebarView", superviewName: "NSTitlebarContainerView"))
        XCTAssertTrue(WindowChromeSuppression.shouldStyleView(named: "NSView", superviewName: "NSTitlebarView"))
        XCTAssertFalse(WindowChromeSuppression.shouldHideView(named: "NSView", topLevel: false))
    }

    func testInitialFrameCentersWindowWithoutCascadeSource() {
        let visibleFrame = NSRect(x: 100, y: 80, width: 1600, height: 1000)
        let contentSize = DocumentWindowController.initialContentSize

        let frame = DocumentWindowController.initialFrame(
            contentSize: contentSize,
            visibleFrame: visibleFrame,
            cascadeFrom: nil
        )

        XCTAssertEqual(frame.origin.x, visibleFrame.midX - (contentSize.width / 2), accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, visibleFrame.midY - (contentSize.height / 2), accuracy: 0.5)
    }

    func testInitialFrameCascadesDownAndRightFromSourceWindow() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let contentSize = DocumentWindowController.initialContentSize
        let sourceFrame = NSRect(x: 300, y: 200, width: contentSize.width, height: contentSize.height)

        let frame = DocumentWindowController.initialFrame(
            contentSize: contentSize,
            visibleFrame: visibleFrame,
            cascadeFrom: sourceFrame
        )

        XCTAssertEqual(frame.origin.x, sourceFrame.minX + DocumentWindowController.cascadeOffset, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, sourceFrame.minY - DocumentWindowController.cascadeOffset, accuracy: 0.5)
    }

    func testStatsAccessoryFormatsUpdatedStatistics() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = DocumentStatisticPreferenceStore(defaults: defaults)
        let windowController = DocumentWindowController(
            contentViewController: NSViewController(),
            statisticPreferenceStore: store
        )
        defer { windowController.close() }

        windowController.apply(documentStatistics: DocumentStatistics(words: 870, minutes: 5, lines: 306, characters: 6708))
        windowController.window?.layoutIfNeeded()

        XCTAssertEqual(windowController.displayedStatisticTextForTesting, "870 Words")
        XCTAssertGreaterThan(windowController.window?.titlebarAccessoryViewControllers.first?.view.frame.width ?? 0, 0)
    }

    func testSidebarStartsClosedDefaultsToDocumentsAndTogglesFromAccessory() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        XCTAssertFalse(windowController.isSidebarVisibleForTesting)
        XCTAssertFalse(windowController.isSidebarAttachedForTesting)
        XCTAssertEqual(windowController.sidebarModeForTesting, .documents)
        XCTAssertFalse(windowController.sidebarButtonIsActiveForTesting)

        windowController.triggerSidebarToggleForTesting()

        XCTAssertTrue(windowController.isSidebarVisibleForTesting)
        XCTAssertTrue(windowController.isSidebarAttachedForTesting)
        XCTAssertTrue(windowController.sidebarButtonIsActiveForTesting)
    }

    func testClosingSidebarDetachesItFromLayout() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        windowController.setReducedMotionForTesting(true)
        windowController.triggerSidebarToggleForTesting()
        XCTAssertTrue(windowController.isSidebarAttachedForTesting)

        windowController.triggerSidebarToggleForTesting()

        XCTAssertFalse(windowController.isSidebarVisibleForTesting)
        XCTAssertFalse(windowController.isSidebarAttachedForTesting)
        XCTAssertEqual(windowController.sidebarWidthForTesting, 0, accuracy: 0.001)
    }

    func testSidebarUsesIndentationFirstOutlineMetrics() {
        XCTAssertEqual(OutlineSidebarMetrics.leadingInset(for: 1), 16, accuracy: 0.001)
        XCTAssertEqual(OutlineSidebarMetrics.leadingInset(for: 2), 32, accuracy: 0.001)
        XCTAssertEqual(OutlineSidebarMetrics.leadingInset(for: 3), 48, accuracy: 0.001)
        XCTAssertEqual(OutlineSidebarMetrics.leadingInset(for: 4), 64, accuracy: 0.001)
        XCTAssertEqual(OutlineSidebarMetrics.leadingInset(for: 5), 80, accuracy: 0.001)
        XCTAssertEqual(OutlineSidebarMetrics.leadingInset(for: 6), 96, accuracy: 0.001)

        XCTAssertEqual(OutlineSidebarMetrics.fontSize, 12.5, accuracy: 0.001)
        XCTAssertEqual(OutlineSidebarMetrics.fontWeight(for: 1, isSelected: false), .semibold)
        XCTAssertEqual(OutlineSidebarMetrics.fontWeight(for: 3, isSelected: false), .regular)
        XCTAssertEqual(OutlineSidebarMetrics.fontWeight(for: 6, isSelected: false), .regular)
    }

    func testSidebarAnimationPreparesCollapsedVisibleOpenState() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        windowController.prepareSidebarForAnimatedOpenForTesting()

        XCTAssertTrue(windowController.isSidebarVisibleForTesting)
        XCTAssertEqual(windowController.sidebarWidthForTesting, 0, accuracy: 0.001)
        XCTAssertEqual(windowController.sidebarAlphaForTesting, 0, accuracy: 0.001)
        XCTAssertEqual(DocumentWindowController.sidebarAnimationDurationForTesting, 0.26, accuracy: 0.001)
    }

    func testSidebarAnimatedOpenKeepsContentFullWidthUntilCompletion() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        windowController.prepareSidebarForAnimatedOpenForTesting()

        XCTAssertTrue(windowController.isSidebarAttachedForTesting)
        XCTAssertFalse(windowController.isContentAlignedWithSidebarForTesting)
        XCTAssertEqual(windowController.sidebarWidthForTesting, 0, accuracy: 0.001)
    }

    func testSidebarReducedMotionPathOpensInstantly() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        windowController.setReducedMotionForTesting(true)
        windowController.triggerSidebarToggleForTesting()

        XCTAssertTrue(windowController.isSidebarVisibleForTesting)
        XCTAssertEqual(windowController.sidebarWidthForTesting, DocumentSidebarViewController.sidebarWidth, accuracy: 0.001)
        XCTAssertEqual(windowController.sidebarAlphaForTesting, 1, accuracy: 0.001)
    }

    func testSidebarToggleDoesNotChangeWindowFrameWidth() throws {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        let window = try XCTUnwrap(windowController.window)
        windowController.showWindow(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let initialWidth = window.frame.width

        windowController.triggerSidebarToggleForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(DocumentWindowController.sidebarAnimationDurationForTesting / 2))
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
        RunLoop.current.run(until: Date().addingTimeInterval(DocumentWindowController.sidebarAnimationDurationForTesting + 0.1))
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)

        windowController.triggerSidebarToggleForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(DocumentWindowController.sidebarAnimationDurationForTesting / 2))
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
        RunLoop.current.run(until: Date().addingTimeInterval(DocumentWindowController.sidebarAnimationDurationForTesting + 0.1))
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
    }

    func testSidebarModeIsWindowLocal() {
        let first = DocumentWindowController(contentViewController: NSViewController())
        let second = DocumentWindowController(contentViewController: NSViewController())
        defer {
            first.close()
            second.close()
        }

        first.setSidebarModeForTesting(.outline)

        XCTAssertEqual(first.sidebarModeForTesting, .outline)
        XCTAssertEqual(second.sidebarModeForTesting, .documents)
    }

    func testSidebarForwardsDocumentAndOutlineSelections() {
        let windowController = DocumentWindowController(contentViewController: NSViewController())
        defer { windowController.close() }

        let linkedURL = URL(fileURLWithPath: "/tmp/docs/Guide.md")
        windowController.apply(
            sidebarEntries: [
                DocumentSidebarEntry(
                    fileURL: linkedURL,
                    displayTitle: "Guide",
                    previewText: "Preview",
                    isCurrent: false,
                    isAvailable: true
                ),
            ],
            outlineItems: [
                DocumentOutlineItem(title: "Intro", level: 1, anchorID: "intro"),
            ]
        )

        var selectedDocumentURL: URL?
        var selectedAnchorID: String?
        windowController.onSelectSidebarDocument = { selectedDocumentURL = $0 }
        windowController.onSelectOutlineItem = { selectedAnchorID = $0 }

        windowController.triggerSidebarDocumentSelectionForTesting(linkedURL)
        windowController.triggerOutlineSelectionForTesting("intro")

        XCTAssertEqual(selectedDocumentURL, linkedURL)
        XCTAssertEqual(selectedAnchorID, "intro")
    }
}

@MainActor
private func recursiveSubviews(in rootView: NSView) -> [NSView] {
    rootView.subviews + rootView.subviews.flatMap(recursiveSubviews(in:))
}
