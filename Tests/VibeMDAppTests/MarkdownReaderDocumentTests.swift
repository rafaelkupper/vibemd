import AppKit
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

@MainActor
final class MarkdownReaderDocumentTests: XCTestCase {
    func testDocumentCreatesConcreteWebKitReaderWindowController() throws {
        let reader = RecordingReaderViewController()
        let document = MarkdownReaderDocument(readerControllerFactory: { reader })
        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Test.md")
        try document.read(from: Data("# Title".utf8), ofType: "dev.vibemd.markdown")
        document.makeWindowControllers()

        XCTAssertTrue(document.windowControllers.first?.contentViewController is WebKitReaderViewController)
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
}
