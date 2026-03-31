import Markdown
import XCTest
@testable import VibeMDCore

final class MarkdownParserTests: XCTestCase {
    private let parser = MarkdownParser()

    func testParserProducesStableFingerprint() {
        let markdown = "# Hello\n\n- one\n- two"

        let document = parser.parse(source: markdown, baseURL: nil)

        XCTAssertEqual(document.fingerprint, FileFingerprint.sha256Hex(for: markdown))
    }

    func testParserPreservesSourceAndBaseURL() {
        let baseURL = URL(fileURLWithPath: "/tmp/readme.md")

        let document = parser.parse(source: "body", baseURL: baseURL)

        XCTAssertEqual(document.source, "body")
        XCTAssertEqual(document.baseURL, baseURL)
    }

    func testParserEnablesBlockDirectivesAndSymbolLinks() {
        let document = parser.parse(
            source: """
            @Note(title: "Heads up") {
            Symbol link: ``ReaderTheme.styleSheet``
            }
            """,
            baseURL: nil
        )

        let blockDirective = firstNode(of: BlockDirective.self, in: document.ast)
        let symbolLink = firstNode(of: SymbolLink.self, in: document.ast)

        XCTAssertEqual(blockDirective?.name, "Note")
        XCTAssertEqual(symbolLink?.destination, "ReaderTheme.styleSheet")
    }

    private func firstNode<T: Markup>(of type: T.Type, in markup: Markup) -> T? {
        if let node = markup as? T {
            return node
        }

        for child in markup.children {
            if let node = firstNode(of: type, in: child) {
                return node
            }
        }

        return nil
    }
}
