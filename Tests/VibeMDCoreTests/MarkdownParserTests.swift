import XCTest
@testable import VibeMDCore

final class MarkdownParserTests: XCTestCase {
    func testParserProducesStableFingerprint() {
        let parser = MarkdownParser()
        let markdown = "# Hello\n\n- one\n- two"

        let document = parser.parse(source: markdown, baseURL: nil)

        XCTAssertEqual(document.fingerprint, FileFingerprint.sha256Hex(for: markdown))
    }

    func testParserPreservesSourceAndBaseURL() {
        let parser = MarkdownParser()
        let baseURL = URL(fileURLWithPath: "/tmp/readme.md")

        let document = parser.parse(source: "body", baseURL: baseURL)

        XCTAssertEqual(document.source, "body")
        XCTAssertEqual(document.baseURL, baseURL)
    }
}

