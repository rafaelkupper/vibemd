import Foundation
import XCTest
@testable import VibeMDCore

final class DocumentSidebarTests: XCTestCase {
    private let parser = MarkdownParser()
    private let assetResolver = AssetResolver()

    func testSidebarEntriesDedupeMarkdownLinksByIdentity() throws {
        let tempDirectory = try CoreTemporaryDirectory()
        defer { tempDirectory.remove() }

        let currentURL = try tempDirectory.createTextFile(
            named: "Current.md",
            contents: """
            # Current Title

            Current preview text.

            [Guide](Guide.md)
            [Guide Again](Guide.md#deep-link)
            [Notes](notes.txt)
            [External](https://example.com)
            [Missing](Missing.md)
            """
        )
        _ = try tempDirectory.createTextFile(
            named: "Guide.md",
            contents: """
            # Guide Title

            First guide paragraph that becomes the preview.
            """
        )

        let document = parser.parse(source: try String(contentsOf: currentURL), baseURL: currentURL)
        let entries = DocumentSidebarDataBuilder.sidebarEntries(from: document, assetResolver: assetResolver)

        XCTAssertEqual(entries.map(\.displayTitle), ["Current Title", "Guide Title", "Missing"])
        XCTAssertEqual(entries.first?.previewText, "Current preview text.")
        XCTAssertEqual(entries[1].previewText, "First guide paragraph that becomes the preview.")
        XCTAssertTrue(entries[0].isCurrent)
        XCTAssertTrue(entries[1].isAvailable)
        XCTAssertFalse(entries[2].isAvailable)
        XCTAssertEqual(entries[0].fileURL, URL(fileURLWithPath: currentURL.standardizedFileURL.path))
    }

    func testSidebarEntriesUseStableDisplayOrderingInsteadOfPromotingCurrentFile() throws {
        let tempDirectory = try CoreTemporaryDirectory()
        defer { tempDirectory.remove() }

        let currentURL = try tempDirectory.createTextFile(
            named: "Current.md",
            contents: """
            # Zeta Current

            Current preview text.

            [Guide](Guide.md)
            """
        )
        _ = try tempDirectory.createTextFile(
            named: "Guide.md",
            contents: """
            # Alpha Guide

            Linked preview text.
            """
        )

        let document = parser.parse(source: try String(contentsOf: currentURL), baseURL: currentURL)
        let entries = DocumentSidebarDataBuilder.sidebarEntries(from: document, assetResolver: assetResolver)

        XCTAssertEqual(entries.map(\.displayTitle), ["Alpha Guide", "Zeta Current"])
        XCTAssertFalse(entries[0].isCurrent)
        XCTAssertTrue(entries[1].isCurrent)
    }

    func testOutlineItemsPreserveHeadingOrderLevelsAndDuplicateSafeAnchors() {
        let document = parser.parse(
            source: """
            # Intro
            ## Details
            ## Details
            ### Deep Dive
            """,
            baseURL: URL(fileURLWithPath: "/tmp/Outline.md")
        )

        let outlineItems = DocumentSidebarDataBuilder.outlineItems(from: document)

        XCTAssertEqual(outlineItems.map(\.title), ["Intro", "Details", "Details", "Deep Dive"])
        XCTAssertEqual(outlineItems.map(\.level), [1, 2, 2, 3])
        XCTAssertEqual(outlineItems.map(\.anchorID), ["intro", "details", "details-2", "deep-dive"])
    }

    func testSidebarPreviewUnderstandsCalloutsSymbolLinksAndInlineAttributes() throws {
        let tempDirectory = try CoreTemporaryDirectory()
        defer { tempDirectory.remove() }

        let currentURL = try tempDirectory.createTextFile(
            named: "Current.md",
            contents: """
            # Current

            [Guide](Guide.md)
            """
        )
        _ = try tempDirectory.createTextFile(
            named: "Guide.md",
            contents: """
            # Guide

            @Tip(title: "Quick hint") {
            Use ``ReaderTheme.styleSheet`` with ^[chip text](class: "md-inline-chip").
            }
            """
        )

        let document = parser.parse(source: try String(contentsOf: currentURL), baseURL: currentURL)
        let entries = DocumentSidebarDataBuilder.sidebarEntries(from: document, assetResolver: assetResolver)

        XCTAssertEqual(entries.map(\.displayTitle), ["Current", "Guide"])
        XCTAssertEqual(entries.last?.previewText, "Quick hint Use ReaderTheme.styleSheet with chip text.")
    }
}

private struct CoreTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createTextFile(named name: String, contents: String) throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
