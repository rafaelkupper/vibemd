import XCTest
@testable import VibeMDCore

final class DocumentStatisticsTests: XCTestCase {
    private let parser = MarkdownParser()

    func testRenderedTextExtractionFollowsVisibleReaderContent() {
        let document = parser.parse(
            source: """
            # Title

            Paragraph with [visible link](https://example.com/docs) and <kbd>Cmd</kbd>.

            - [x] Completed item
            - Plain item

            > Quoted line

            ```swift
            let title = "VibeMD"
            ```

            | Name | Value |
            | --- | --- |
            | One | 1 |

            ![Screenshot](Preview.png)

            <aside>raw html</aside>

            :::note
            Important
            :::
            """,
            baseURL: nil
        )

        let renderedText = RenderedTextDocumentStatistics.renderedText(from: document)

        XCTAssertTrue(renderedText.contains("Title"))
        XCTAssertTrue(renderedText.contains("visible link"))
        XCTAssertTrue(renderedText.contains("Cmd"))
        XCTAssertTrue(renderedText.contains("Completed item"))
        XCTAssertTrue(renderedText.contains("Quoted line"))
        XCTAssertTrue(renderedText.contains("let title = \"VibeMD\""))
        XCTAssertTrue(renderedText.contains("Name Value"))
        XCTAssertTrue(renderedText.contains("raw html"))
        XCTAssertTrue(renderedText.contains("Important"))
        XCTAssertFalse(renderedText.contains("https://example.com/docs"))
        XCTAssertFalse(renderedText.contains("Preview.png"))
        XCTAssertFalse(renderedText.contains("Screenshot"))
    }

    func testStatisticsUseEditorialDefaultsAndLogicalNonEmptyLines() {
        let statistics = RenderedTextDocumentStatistics.statistics(fromRenderedText: "One two\nThree")

        XCTAssertEqual(statistics.words, 3)
        XCTAssertEqual(statistics.minutes, 1)
        XCTAssertEqual(statistics.lines, 2)
        XCTAssertEqual(statistics.characters, 13)
    }

    func testEmptyAndSingleWordStatisticsHandleMinuteFloorCorrectly() {
        let empty = RenderedTextDocumentStatistics.statistics(fromRenderedText: "")
        let singleWord = RenderedTextDocumentStatistics.statistics(fromRenderedText: "VibeMD")

        XCTAssertEqual(empty, .zero)
        XCTAssertEqual(singleWord.words, 1)
        XCTAssertEqual(singleWord.minutes, 1)
        XCTAssertEqual(singleWord.lines, 1)
        XCTAssertEqual(singleWord.characters, 6)
    }
}
