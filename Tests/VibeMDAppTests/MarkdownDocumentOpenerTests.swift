import AppKit
import XCTest
@testable import VibeMDApp

@MainActor
final class MarkdownDocumentOpenerTests: XCTestCase {
    func testSupportsRecognizedMarkdownExtensionsOnly() {
        XCTAssertTrue(MarkdownDocumentOpener.supports(url: URL(fileURLWithPath: "/tmp/docs/readme.md")))
        XCTAssertTrue(MarkdownDocumentOpener.supports(url: URL(fileURLWithPath: "/tmp/docs/readme.markdown")))
        XCTAssertFalse(MarkdownDocumentOpener.supports(url: URL(fileURLWithPath: "/tmp/docs/readme.txt")))
        XCTAssertFalse(MarkdownDocumentOpener.supports(url: URL(string: "https://example.com/readme.md")!))
    }

    func testOpenRetainsDocumentUntilItCloses() throws {
        _ = NSApplication.shared
        defer { closeOpenMarkdownDocuments() }
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let fileURL = try tempDirectory.createTextFile(named: "Retain.md", contents: "# Retain\n\nBody")
        let initialRetainedCount = MarkdownDocumentOpener.retainedDocumentCountForTesting

        try MarkdownDocumentOpener.open(url: fileURL)

        XCTAssertEqual(MarkdownDocumentOpener.retainedDocumentCountForTesting, initialRetainedCount + 1)

        let openedDocument = try XCTUnwrap(
            NSDocumentController.shared.documents
                .compactMap { $0 as? MarkdownReaderDocument }
                .last(where: { $0.fileURL == fileURL })
        )

        openedDocument.close()

        XCTAssertEqual(MarkdownDocumentOpener.retainedDocumentCountForTesting, initialRetainedCount)
    }

    func testOpeningSameFileTwiceReusesExistingDocument() throws {
        _ = NSApplication.shared
        defer { closeOpenMarkdownDocuments() }
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let fileURL = try tempDirectory.createTextFile(named: "Reuse.md", contents: "# Reuse")

        try MarkdownDocumentOpener.open(url: fileURL)
        let initialDocuments = openMarkdownDocuments()
        let initialWindows = initialDocuments.flatMap(\.windowControllers).compactMap(\.window)

        try MarkdownDocumentOpener.open(url: fileURL)

        let finalDocuments = openMarkdownDocuments()
        XCTAssertEqual(finalDocuments.count, 1)
        XCTAssertEqual(initialDocuments.first, finalDocuments.first)
        XCTAssertEqual(initialWindows.first, finalDocuments.first?.windowControllers.first?.window)
    }

    func testOpeningFileWithFragmentReusesExistingDocument() throws {
        _ = NSApplication.shared
        defer { closeOpenMarkdownDocuments() }
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let fileURL = try tempDirectory.createTextFile(named: "Fragment.md", contents: "# Fragment")
        var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
        components?.fragment = "section-1"
        let fileURLWithFragment = try XCTUnwrap(components?.url)

        try MarkdownDocumentOpener.open(url: fileURL)
        try MarkdownDocumentOpener.open(url: fileURLWithFragment)

        let documents = openMarkdownDocuments()
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.fileURL, MarkdownDocumentOpener.normalizedFileURL(for: fileURL))
    }

    func testOpeningDifferentFileCreatesSecondDocumentAndCascadesWindow() throws {
        _ = NSApplication.shared
        defer { closeOpenMarkdownDocuments() }
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let firstURL = try tempDirectory.createTextFile(named: "One.md", contents: "# One")
        let secondURL = try tempDirectory.createTextFile(named: "Two.md", contents: "# Two")

        try MarkdownDocumentOpener.open(url: firstURL)
        let firstDocument = try XCTUnwrap(openMarkdownDocuments().last)
        let firstWindow = try XCTUnwrap(firstDocument.windowControllers.first?.window)

        try MarkdownDocumentOpener.open(url: secondURL)

        let documents = openMarkdownDocuments()
        XCTAssertEqual(documents.count, 2)
        let secondDocument = try XCTUnwrap(documents.last(where: { $0.fileURL == secondURL }))
        let secondWindow = try XCTUnwrap(secondDocument.windowControllers.first?.window)

        XCTAssertEqual(secondWindow.frame.minX, firstWindow.frame.minX + DocumentWindowController.cascadeOffset, accuracy: 1)
        XCTAssertEqual(secondWindow.frame.minY, firstWindow.frame.minY - DocumentWindowController.cascadeOffset, accuracy: 1)
        XCTAssertTrue(secondWindow.isVisible)
        XCTAssertTrue(MarkdownDocumentOpener.currentMarkdownWindowForTesting() === secondWindow)
    }

    func testNormalOpenStillReusesPreferredWindowWhenMultipleDocumentsTrackSameFile() throws {
        _ = NSApplication.shared
        defer { closeOpenMarkdownDocuments() }
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let firstURL = try tempDirectory.createTextFile(named: "One.md", contents: "# One")
        let secondURL = try tempDirectory.createTextFile(named: "Two.md", contents: "# Two")

        try MarkdownDocumentOpener.open(url: firstURL)
        try MarkdownDocumentOpener.open(url: secondURL)

        let secondDocument = try XCTUnwrap(
            openMarkdownDocuments().first(where: { $0.fileURL == secondURL })
        )
        secondDocument.navigateInCurrentWindow(to: firstURL)

        let navigationExpectation = expectation(description: "same-window navigation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            navigationExpectation.fulfill()
        }
        wait(for: [navigationExpectation], timeout: 2)

        XCTAssertEqual(openMarkdownDocuments().filter { $0.fileURL == firstURL }.count, 2)

        try MarkdownDocumentOpener.open(url: firstURL)

        XCTAssertEqual(openMarkdownDocuments().count, 2)
    }

    private func openMarkdownDocuments() -> [MarkdownReaderDocument] {
        NSDocumentController.shared.documents.compactMap { $0 as? MarkdownReaderDocument }
    }

    private func closeOpenMarkdownDocuments() {
        openMarkdownDocuments().forEach { $0.close() }
    }
}
