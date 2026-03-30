import XCTest
@testable import VibeMDCore

final class WebKitHTMLRendererTests: XCTestCase {
    private let parser = MarkdownParser()
    private let renderer = WebKitHTMLRenderer()

    func testRendererProducesHTMLForCommonMarkdownFeatures() {
        let baseURL = URL(fileURLWithPath: "/tmp/rendering/Showcase.md")
        let source = """
        # Title

        Paragraph with [link](https://example.com) and <kbd>Cmd</kbd> + <kbd>O</kbd>.

        > Quoted line

        - [x] done

        ```swift
        struct ReaderTheme {
            let readableWidth = 760
        }
        ```

        | Name | Value |
        | --- | --- |
        | One | 1 |

        ![Preview](App/Resources/VibeMD-preview.png)

        ---

        <aside>raw html</aside>

        :::note
        Hello
        :::
        """

        let output = render(source, baseURL: baseURL)

        XCTAssertEqual(output.baseURL, baseURL.deletingLastPathComponent())
        XCTAssertTrue(output.html.contains("<div id=\"write\">"))
        XCTAssertTrue(output.html.contains("--bg-color: #383E44;"))
        XCTAssertTrue(output.html.contains("--text-color: #BCC3CA;"))
        XCTAssertTrue(output.html.contains("--link-color: #D7DDE3;"))
        XCTAssertTrue(output.html.contains("--rule-color: #4C525A;"))
        XCTAssertTrue(output.html.contains("--code-block-bg: #2F3135;"))
        XCTAssertTrue(output.html.contains("font-family: \"Helvetica Neue\", Helvetica, Arial, \"Segoe UI Emoji\", \"SF Pro\", sans-serif;"))
        XCTAssertTrue(output.html.contains("font-family: \"Lucida Grande\", \"Corbel\", sans-serif;"))
        XCTAssertTrue(output.html.contains("font-family: Monaco, Consolas, \"Andale Mono\", \"DejaVu Sans Mono\", monospace;"))
        XCTAssertTrue(output.html.contains("max-width: 928px;"))
        XCTAssertTrue(output.html.contains("@media only screen and (min-width: 1400px)"))
        XCTAssertTrue(output.html.contains("line-height: 1.66rem;"))
        XCTAssertTrue(output.html.contains("padding: 11px 11px 11px 31px;"))
        XCTAssertTrue(output.html.contains("<h1>Title</h1>"))
        XCTAssertTrue(output.html.contains("<blockquote>"))
        XCTAssertTrue(output.html.contains("border-left: solid 2px var(--rule-color);"))
        XCTAssertTrue(output.html.contains("class=\"task-list\""))
        XCTAssertTrue(output.html.contains("class=\"md-task-list-item\""))
        XCTAssertTrue(output.html.contains("type=\"checkbox\" disabled checked"))
        XCTAssertTrue(output.html.contains("<table>"))
        XCTAssertTrue(output.html.contains("<hr />"))
        XCTAssertTrue(output.html.contains("<kbd>Cmd</kbd>"))
        XCTAssertTrue(output.html.contains("border: 1px solid #727880;"))
        XCTAssertTrue(output.html.contains("<pre class=\"md-fences\""))
        XCTAssertTrue(output.html.contains("class=\"cm-s-inner"))
        XCTAssertTrue(output.html.contains("href=\"https://example.com\""))
        XCTAssertTrue(output.html.contains("src=\"vibemd-local://asset?path="))
        XCTAssertTrue(output.html.contains("VibeMD-preview.png"))
        XCTAssertTrue(output.html.contains("raw html"))
        XCTAssertTrue(output.html.contains(":::note"))
    }

    func testTaggedCodeBlocksEmitTokenSpansWhilePlainCodeRemainsUnstyled() {
        let swiftOutput = render(
            """
            ```swift
            struct Theme {
                let title = "VibeMD"
            }
            ```
            """
        )
        let plainOutput = render(
            """
            ```
            plain code
            ```
            """
        )

        XCTAssertTrue(swiftOutput.html.contains("<span class=\"cm-keyword\">"))
        XCTAssertTrue(swiftOutput.html.contains("<span class=\"cm-def\">"))
        XCTAssertTrue(swiftOutput.html.contains("<span class=\"cm-string\">"))
        XCTAssertTrue(swiftOutput.html.contains("<pre class=\"md-fences\" lang=\"swift\"><code class=\"cm-s-inner language-swift\">"))
        XCTAssertFalse(plainOutput.html.contains("<span class=\"cm-keyword\">"))
        XCTAssertFalse(plainOutput.html.contains("<span class=\"cm-def\">"))
    }

    func testTableColumnWidthsCoverPresetAndHeuristicLayouts() {
        let threeColumnOutput = render(
            """
            | A | B | C |
            | - | - | - |
            | 1 | 2 | 3 |
            """
        )
        let fourColumnOutput = render(
            """
            | A | B | C | D |
            | - | - | - | - |
            | 1 | 2 | 3 | 4 |
            """
        )
        let heuristicOutput = render(
            """
            | Feature | Description | Impact | Area | Score |
            | --- | --- | --- | --- | --- |
            | Rendering | Longer descriptive copy to widen the column | High | Reader | 9 |
            """
        )

        XCTAssertTrue(threeColumnOutput.html.contains("<col style=\"width: 20.0%\">"))
        XCTAssertTrue(threeColumnOutput.html.contains("<col style=\"width: 30.0%\">"))
        XCTAssertTrue(threeColumnOutput.html.contains("<col style=\"width: 50.0%\">"))
        XCTAssertTrue(fourColumnOutput.html.contains("<col style=\"width: 15.0%\">"))
        XCTAssertTrue(fourColumnOutput.html.contains("<col style=\"width: 22.0%\">"))
        XCTAssertTrue(fourColumnOutput.html.contains("<col style=\"width: 51.0%\">"))
        XCTAssertTrue(fourColumnOutput.html.contains("<col style=\"width: 12.0%\">"))
        XCTAssertEqual(heuristicOutput.html.numberOfMatches(of: "<col style=\"width:"), 5)
    }

    func testNestedListsAndTaskListsRenderNestedHTML() {
        let output = render(
            """
            - Top level
              - Nested bullet
              - [x] Nested task
            - [ ] Top task
              - [x] Nested checked task
            """
        )

        XCTAssertGreaterThanOrEqual(output.html.numberOfMatches(of: "<ul"), 3)
        XCTAssertGreaterThanOrEqual(output.html.numberOfMatches(of: "class=\"task-list\""), 2)
        XCTAssertGreaterThanOrEqual(output.html.numberOfMatches(of: "class=\"md-task-list-item\""), 3)
    }

    func testRelativeMarkdownLinksPreserveFragmentsInHTML() {
        let baseURL = URL(fileURLWithPath: "/tmp/docs/README.md")
        let output = render(
            """
            [Guide](guide/intro.md#deep-link)
            [Here](#top)
            """,
            baseURL: baseURL
        )

        XCTAssertTrue(output.html.contains("href=\"guide/intro.md#deep-link\""))
        XCTAssertTrue(output.html.contains("href=\"README.md#top\""))
    }

    func testMissingAndRemoteImagesFallBackToPlaceholderBlocks() {
        let output = render(
            """
            ![Missing]()
            ![Remote](https://example.com/image.png)
            """
        )

        XCTAssertEqual(output.html.numberOfMatches(of: "[Missing image]"), 2)
        XCTAssertFalse(output.html.contains("https://example.com/image.png"))
    }

    func testRendererEscapesTextAttributesAndCode() {
        let output = render(
            """
            5 < 7 & 9 > 3

            [Params](https://example.com?q=chips&lang=md)

            ```
            <div class="notice">& "quoted"</div>
            ```
            """
        )

        XCTAssertTrue(output.html.contains("5 &lt; 7 &amp; 9 &gt; 3"))
        XCTAssertTrue(output.html.contains("href=\"https://example.com?q=chips&amp;lang=md\""))
        XCTAssertTrue(output.html.contains("&lt;div class=&quot;notice&quot;&gt;&amp; &quot;quoted&quot;&lt;/div&gt;"))
    }

    func testRawHTMLBlockDirectivesAndKbdHandlingRemainVisible() {
        let output = render(
            """
            Raw <span>inline</span> html and <kbd>Cmd</kbd>.

            <aside>block html</aside>

            :::note
            Important
            :::
            """
        )

        XCTAssertTrue(output.html.contains("Raw inline html and <kbd>Cmd</kbd>."))
        XCTAssertTrue(output.html.contains("<p class=\"fallback-block\">block html</p>"))
        XCTAssertTrue(output.html.contains(":::note"))
        XCTAssertTrue(output.html.contains("Important"))
    }

    private func render(_ source: String, baseURL: URL? = nil) -> WebKitRenderOutput {
        let document = parser.parse(source: source, baseURL: baseURL)
        return renderer.render(document: document)
    }
}

private extension String {
    func numberOfMatches(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
