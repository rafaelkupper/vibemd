import AppKit
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

@MainActor
final class MarkdownReaderDocumentTests: XCTestCase {
    func testObjectiveCNewPathCanInstantiateMarkdownDocument() throws {
        let document = try XCTUnwrap(
            (MarkdownReaderDocument.self as AnyObject)
                .perform(NSSelectorFromString("new"))?
                .takeRetainedValue() as? MarkdownReaderDocument
        )

        document.close()
    }

    func testDocumentCreatesConcreteWebKitReaderWindowController() throws {
        let reader = RecordingReaderViewController()
        let document = MarkdownReaderDocument(readerControllerFactory: { reader })
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Test.md")
        try document.read(from: Data("# Title".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()

        let windowController = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        XCTAssertTrue(windowController.hostedContentViewController is WebKitReaderViewController)
        document.close()
    }

    func testSchedulesRenderAfterReadAndWindowCreation() throws {
        let reader = RecordingReaderViewController()
        var scheduledSource: String?
        var capturedCompletion: ((WebKitRenderOutput) -> Void)?
        let document = MarkdownReaderDocument(
            renderScheduler: { source, _, completion in
                scheduledSource = source
                capturedCompletion = completion
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader }
        )
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Guide.md")

        try document.read(from: Data("# Guide".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()

        XCTAssertEqual(scheduledSource, "# Guide")
        XCTAssertEqual(reader.displayedLoadingNames.last, "Guide.md")

        capturedCompletion?(WebKitRenderOutput(html: "<html><body>Done</body></html>", baseURL: nil))

        XCTAssertEqual(reader.appliedOutputs.count, 1)
        XCTAssertEqual(reader.appliedOutputs.first?.html, "<html><body>Done</body></html>")
        document.close()
    }

    func testRenderCompletionUpdatesWindowStatistics() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = DocumentStatisticPreferenceStore(defaults: defaults)
        let reader = RecordingReaderViewController()
        var capturedCompletion: ((WebKitRenderOutput) -> Void)?
        let document = MarkdownReaderDocument(
            renderScheduler: { _, _, completion in
                capturedCompletion = completion
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader },
            statisticPreferenceStore: store
        )
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Stats.md")

        try document.read(from: Data("# Stats".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()

        let windowController = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        XCTAssertNil(windowController.displayedStatisticTextForTesting)

        capturedCompletion?(
            WebKitRenderOutput(
                html: "<html><body>Stats</body></html>",
                baseURL: nil,
                statistics: DocumentStatistics(words: 12, minutes: 1, lines: 3, characters: 64),
                sidebarEntries: [
                    DocumentSidebarEntry(
                        fileURL: URL(fileURLWithPath: "/tmp/Stats.md"),
                        displayTitle: "Stats",
                        previewText: "Preview",
                        isCurrent: true,
                        isAvailable: true
                    ),
                ],
                outlineItems: [
                    DocumentOutlineItem(title: "Stats", level: 1, anchorID: "stats"),
                ]
            )
        )

        XCTAssertEqual(windowController.displayedStatisticTextForTesting, "12 Words")
        XCTAssertEqual(windowController.sidebarDocumentTitlesForTesting, ["Stats"])
        XCTAssertEqual(windowController.outlineTitlesForTesting, ["Stats"])
        document.close()
    }

    func testRestoresPersistedScrollFractionIntoRenderedReader() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ScrollStateStore(defaults: defaults)
        let reader = RecordingReaderViewController()
        var capturedCompletion: ((WebKitRenderOutput) -> Void)?
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Restore.md")
        let data = Data("# Restore".utf8)
        let fingerprint = FileFingerprint.sha256Hex(for: data)
        store.save(fraction: 0.42, for: fileURL, fingerprint: fingerprint)

        let document = MarkdownReaderDocument(
            scrollStateStore: store,
            renderScheduler: { _, _, completion in
                capturedCompletion = completion
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader }
        )
        document.fileURL = fileURL

        try document.read(from: data, ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()
        capturedCompletion?(WebKitRenderOutput(html: "<html><body>Rendered</body></html>", baseURL: nil))

        XCTAssertEqual(try XCTUnwrap(reader.appliedInitialScrollFractions.last ?? nil), 0.42, accuracy: 0.0001)
        document.close()
    }

    func testPersistsCurrentScrollFractionOnClose() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ScrollStateStore(defaults: defaults)
        let reader = RecordingReaderViewController()
        reader.stubbedCurrentScrollFraction = 0.73

        let document = MarkdownReaderDocument(
            scrollStateStore: store,
            renderScheduler: { _, _, _ in DispatchWorkItem {} },
            readerControllerFactory: { reader }
        )
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Persist.md")
        let data = Data("# Persist".utf8)
        let fingerprint = FileFingerprint.sha256Hex(for: data)
        document.fileURL = fileURL

        try document.read(from: data, ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()
        document.close()

        let saved = store.load(for: fileURL, fingerprint: fingerprint)
        XCTAssertEqual(saved?.fraction ?? -1, 0.73, accuracy: 0.0001)
    }

    func testIgnoresStaleAsyncRenderCompletions() throws {
        let reader = RecordingReaderViewController()
        var completions: [(WebKitRenderOutput) -> Void] = []
        let document = MarkdownReaderDocument(
            renderScheduler: { _, _, completion in
                completions.append(completion)
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader }
        )
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Async.md")

        try document.read(from: Data("# First".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()
        try document.read(from: Data("# Second".utf8), ofType: "dev.vibemd.markdown")

        XCTAssertEqual(completions.count, 2)

        completions[0](WebKitRenderOutput(html: "<html>old</html>", baseURL: nil))
        XCTAssertTrue(reader.appliedOutputs.isEmpty)

        completions[1](WebKitRenderOutput(html: "<html>new</html>", baseURL: nil))
        XCTAssertEqual(reader.appliedOutputs.count, 1)
        XCTAssertEqual(reader.appliedOutputs.first?.html, "<html>new</html>")
        document.close()
    }

    func testRoutesLinksThroughInjectedTargetHandler() throws {
        let reader = RecordingReaderViewController()
        var handledTargets: [LinkTarget] = []
        let document = MarkdownReaderDocument(
            renderScheduler: { _, _, _ in DispatchWorkItem {} },
            linkTargetHandler: { handledTargets.append($0) },
            readerControllerFactory: { reader }
        )
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Links.md")

        try document.read(from: Data("# Links".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()

        reader.onOpenLink?(URL(string: "https://example.com")!)
        reader.onOpenLink?(URL(fileURLWithPath: "/tmp/docs/Guide.md"))
        reader.onOpenLink?(URL(fileURLWithPath: "/tmp/docs/notes.txt"))

        XCTAssertEqual(handledTargets.count, 3)
        XCTAssertEqual(handledTargets[0], .external(URL(string: "https://example.com")!))
        XCTAssertEqual(handledTargets[1], .markdownFile(URL(fileURLWithPath: "/tmp/docs/Guide.md")))
        XCTAssertEqual(handledTargets[2], .otherFile(URL(fileURLWithPath: "/tmp/docs/notes.txt")))
        document.close()
    }

    func testSidebarNavigationReplacesCurrentFileInSameWindow() throws {
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let firstURL = try tempDirectory.createTextFile(named: "One.md", contents: "# One")
        let secondURL = try tempDirectory.createTextFile(named: "Two.md", contents: "# Two")

        let reader = RecordingReaderViewController()
        var scheduledURLs: [URL] = []
        var completions: [(WebKitRenderOutput) -> Void] = []
        let secondRenderScheduled = expectation(description: "second render scheduled")
        let document = MarkdownReaderDocument(
            renderScheduler: { _, baseURL, completion in
                if let baseURL {
                    scheduledURLs.append(baseURL)
                }
                completions.append(completion)
                if baseURL == secondURL {
                    secondRenderScheduled.fulfill()
                }
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader }
        )
        document.fileURL = firstURL

        try document.read(from: Data("# One".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()
        completions[0](WebKitRenderOutput(html: "<html>one</html>", baseURL: nil))

        document.navigateInCurrentWindow(to: secondURL)

        wait(for: [secondRenderScheduled], timeout: 5)
        let windowController = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        XCTAssertEqual(document.fileURL, secondURL)
        XCTAssertEqual(windowController.window?.title, "Two.md")
        XCTAssertEqual(reader.displayedLoadingNames.last, "Two.md")
        XCTAssertEqual(scheduledURLs.last, secondURL)

        completions[1](
            WebKitRenderOutput(
                html: "<html>two</html>",
                baseURL: nil,
                statistics: DocumentStatistics(words: 8, minutes: 1, lines: 2, characters: 32),
                sidebarEntries: [
                    DocumentSidebarEntry(
                        fileURL: secondURL,
                        displayTitle: "Two",
                        previewText: "Second preview",
                        isCurrent: true,
                        isAvailable: true
                    ),
                ],
                outlineItems: [
                    DocumentOutlineItem(title: "Two", level: 1, anchorID: "two"),
                ]
            )
        )

        XCTAssertEqual(windowController.displayedStatisticTextForTesting, "8 Words")
        XCTAssertEqual(windowController.sidebarDocumentTitlesForTesting, ["Two"])
        XCTAssertEqual(windowController.outlineTitlesForTesting, ["Two"])
        document.close()
    }

    func testSidebarNavigationPersistsOldScrollAndRestoresTargetScroll() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ScrollStateStore(defaults: defaults)
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let firstContents = "# One"
        let secondContents = "# Two"
        let firstURL = try tempDirectory.createTextFile(named: "One.md", contents: firstContents)
        let secondURL = try tempDirectory.createTextFile(named: "Two.md", contents: secondContents)

        let firstFingerprint = FileFingerprint.sha256Hex(for: Data(firstContents.utf8))
        let secondFingerprint = FileFingerprint.sha256Hex(for: Data(secondContents.utf8))
        store.save(fraction: 0.41, for: secondURL, fingerprint: secondFingerprint)

        let reader = RecordingReaderViewController()
        reader.stubbedCurrentScrollFraction = 0.73

        var completions: [(WebKitRenderOutput) -> Void] = []
        let secondRenderScheduled = expectation(description: "second render scheduled")
        let document = MarkdownReaderDocument(
            scrollStateStore: store,
            renderScheduler: { _, baseURL, completion in
                completions.append(completion)
                if baseURL == secondURL {
                    secondRenderScheduled.fulfill()
                }
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader }
        )
        document.fileURL = firstURL

        try document.read(from: Data(firstContents.utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()
        completions[0](WebKitRenderOutput(html: "<html>one</html>", baseURL: nil))

        document.navigateInCurrentWindow(to: secondURL)
        wait(for: [secondRenderScheduled], timeout: 5)
        completions[1](WebKitRenderOutput(html: "<html>two</html>", baseURL: nil))

        XCTAssertEqual(store.load(for: firstURL, fingerprint: firstFingerprint)?.fraction ?? -1, 0.73, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(reader.appliedInitialScrollFractions.last ?? nil), 0.41, accuracy: 0.0001)
        document.close()
    }

    func testOutlineSelectionScrollsReaderToHeading() throws {
        let reader = RecordingReaderViewController()
        var capturedCompletion: ((WebKitRenderOutput) -> Void)?
        let document = MarkdownReaderDocument(
            renderScheduler: { _, _, completion in
                capturedCompletion = completion
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader }
        )
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Outline.md")

        try document.read(from: Data("# Outline".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()
        capturedCompletion?(
            WebKitRenderOutput(
                html: "<html><body>Outline</body></html>",
                baseURL: nil,
                outlineItems: [DocumentOutlineItem(title: "Outline", level: 1, anchorID: "outline")]
            )
        )

        let windowController = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        windowController.triggerOutlineSelectionForTesting("outline")

        XCTAssertEqual(reader.scrolledHeadingIDs, ["outline"])
        document.close()
    }

    func testActiveHeadingUpdatesWindowOutlineSelection() throws {
        let reader = RecordingReaderViewController()
        var capturedCompletion: ((WebKitRenderOutput) -> Void)?
        let document = MarkdownReaderDocument(
            renderScheduler: { _, _, completion in
                capturedCompletion = completion
                return DispatchWorkItem {}
            },
            readerControllerFactory: { reader }
        )
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Outline.md")

        try document.read(from: Data("# Outline".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()
        capturedCompletion?(
            WebKitRenderOutput(
                html: "<html><body>Outline</body></html>",
                baseURL: nil,
                outlineItems: [DocumentOutlineItem(title: "Outline", level: 1, anchorID: "outline")]
            )
        )

        let windowController = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        reader.onActiveHeadingChange?("outline")

        XCTAssertEqual(windowController.activeOutlineAnchorIDForTesting, "outline")
        document.close()
    }
}
