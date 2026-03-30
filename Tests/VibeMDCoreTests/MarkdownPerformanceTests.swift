import XCTest
@testable import VibeMDCore

final class MarkdownPerformanceTests: XCTestCase {
    func testParseAndRenderMediumDocumentPerformance() {
        let parser = MarkdownParser()
        let renderer = WebKitHTMLRenderer()
        let block = """
        ## Section

        Paragraph with **bold**, *italic*, `code`, [link](https://example.com), and a table:

        | Name | Value |
        | ---- | ----- |
        | One  | 1     |
        | Two  | 2     |

        - [x] done
        - [ ] todo

        > Block quote content for layout testing.

        ```swift
        let sample = true
        let veryLongLine = "This line should wrap inside the readable content column without requiring horizontal scrolling in the viewer."
        ```

        | Feature | Notes |
        | ------- | ----- |
        | Quotes  | WebKit block styling |
        | Tables  | Responsive HTML table styling |
        | Lists   | Consistent nested markers |

        ```bash
        ./scripts/build-app.sh release
        open build/VibeMD.app
        ```

        """
        let source = String(repeating: block, count: 250)

        measure {
            let document = parser.parse(source: source, baseURL: nil)
            _ = renderer.render(document: document)
        }
    }
}
