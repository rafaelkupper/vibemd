import Foundation
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

        @Note {
        Hello
        }
        """

        let output = render(source, baseURL: baseURL)

        XCTAssertEqual(output.baseURL, baseURL.deletingLastPathComponent())
        XCTAssertGreaterThan(output.statistics.words, 0)
        XCTAssertGreaterThan(output.statistics.lines, 0)
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
        XCTAssertTrue(output.html.contains(".cm-s-inner .cm-property {"))
        XCTAssertTrue(output.html.contains(".cm-s-inner .cm-atom {"))
        XCTAssertTrue(output.html.contains(".cm-s-inner .cm-variable-2 {"))
        XCTAssertTrue(output.html.contains("<h1 id=\"title\">Title</h1>"))
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
        XCTAssertTrue(output.html.contains("class=\"md-callout md-callout-note\""))
        XCTAssertTrue(output.html.contains("<div class=\"md-callout-label\">Note</div>"))
        XCTAssertEqual(output.outlineItems.first?.anchorID, "title")
    }

    func testSupportedBlockDirectivesRenderAsSemanticCalloutsAndPreserveNestedMarkdown() {
        let output = render(
            """
            @Warning(title: "Heads up") {
            Body with **strong** emphasis and `inline code`.
            }
            """
        )

        XCTAssertTrue(output.html.contains("<aside class=\"md-callout md-callout-warning\">"))
        XCTAssertTrue(output.html.contains("<div class=\"md-callout-label\">Heads up</div>"))
        XCTAssertTrue(output.html.contains("<strong>strong</strong>"))
        XCTAssertTrue(output.html.contains("<code>inline code</code>"))
    }

    func testUnknownBlockDirectivesRemainFallbackBlocks() {
        let output = render(
            """
            @Custom(style: "glass") {
            Mystery block
            }
            """
        )

        XCTAssertTrue(output.html.contains("<p class=\"fallback-block\">"))
        XCTAssertTrue(output.html.contains("@Custom"))
        XCTAssertTrue(output.html.contains("Mystery block"))
    }

    func testSymbolLinksRenderAsCodeVoice() {
        let output = render("Use ``ReaderTheme.styleSheet`` for preview.")

        XCTAssertTrue(output.html.contains("<code class=\"md-symbol-link\">ReaderTheme.styleSheet</code>"))
    }

    func testInlineAttributesPreserveClassOnlyAndIgnoreOtherKeys() {
        let output = render(#"^[chip text](class: "md-inline-chip", demo: "ignored")"#)

        XCTAssertTrue(output.html.contains("<span class=\"md-inline-chip\">chip text</span>"))
        XCTAssertFalse(output.html.contains("demo="))
    }

    func testMalformedInlineAttributesFallBackToChildrenWithoutWrapper() {
        let output = render(#"^[plain text](class: )"#)

        XCTAssertTrue(output.html.contains("<p>plain text</p>"))
        XCTAssertFalse(output.html.contains("<span class="))
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

    func testAliasTaggedCodeBlocksHighlightAndPreserveOriginalLanguageTag() {
        let jsxOutput = render(
            """
            ```jsx
            const renderCard = (props) => props.title
            ```
            """
        )
        let tsxOutput = render(
            """
            ```tsx
            interface Props { title: string }
            const renderCard = (props: Props) => props.title
            ```
            """
        )

        XCTAssertTrue(jsxOutput.html.contains("<pre class=\"md-fences\" lang=\"jsx\"><code class=\"cm-s-inner language-jsx\">"))
        XCTAssertTrue(jsxOutput.html.contains("cm-keyword"))
        XCTAssertTrue(jsxOutput.html.contains("cm-variable-2"))
        XCTAssertTrue(jsxOutput.html.contains("cm-property"))

        XCTAssertTrue(tsxOutput.html.contains("<pre class=\"md-fences\" lang=\"tsx\"><code class=\"cm-s-inner language-tsx\">"))
        XCTAssertTrue(tsxOutput.html.contains("cm-keyword"))
        XCTAssertTrue(tsxOutput.html.contains("cm-def"))
        XCTAssertTrue(tsxOutput.html.contains("cm-variable-2"))
        XCTAssertTrue(tsxOutput.html.contains("cm-property"))
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

    func testTableCellsRenderInlineMarkdownInsteadOfEscapedSourceText() {
        let output = render(
            #"""
            | **Name** | Value |
            | :-- | --: |
            | `code` and [link](https://example.com) | **bold** with *emphasis* and ~~gone~~ |
            """#
        )

        XCTAssertTrue(output.html.contains("<th align=\"left\"><strong>Name</strong></th>"))
        XCTAssertTrue(output.html.contains("<th align=\"right\">Value</th>"))
        XCTAssertTrue(output.html.contains("<td align=\"left\"><code>code</code> and <a href=\"https://example.com\">link</a></td>"))
        XCTAssertTrue(output.html.contains("<td align=\"right\"><strong>bold</strong> with <em>emphasis</em> and <del>gone</del></td>"))
        XCTAssertFalse(output.html.contains("**bold**"))
        XCTAssertFalse(output.html.contains("`code`"))
        XCTAssertFalse(output.html.contains("~~gone~~"))
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

    func testRawHTMLUnknownDirectivesAndKbdHandlingRemainVisible() {
        let output = render(
            """
            Raw <span>inline</span> html and <kbd>Cmd</kbd>.

            <aside>block html</aside>

            @Unknown {
            Important
            }
            """
        )

        XCTAssertTrue(output.html.contains("Raw inline html and <kbd>Cmd</kbd>."))
        XCTAssertTrue(output.html.contains("<p class=\"fallback-block\">block html</p>"))
        XCTAssertTrue(output.html.contains("@Unknown"))
        XCTAssertTrue(output.html.contains("Important"))
    }

    func testRendererProducesSidebarMetadataForCurrentDocumentAndLinkedMarkdownFiles() {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let linkedURL = temporaryDirectory.appendingPathComponent("Guide.md")
        try? Data("# Linked Guide\n\nLinked preview text.".utf8).write(to: linkedURL)
        let currentURL = temporaryDirectory.appendingPathComponent("Showcase.md")
        let source = """
        # Showcase Title

        Current preview text.

        [Guide](Guide.md)
        [Guide Again](Guide.md#section)
        [License](LICENSE)
        """
        let output = render(source, baseURL: currentURL)

        XCTAssertEqual(output.sidebarEntries.map(\.displayTitle), ["Linked Guide", "Showcase Title"])
        XCTAssertEqual(output.sidebarEntries.last?.previewText, "Current preview text.")
        XCTAssertEqual(output.outlineItems.map(\.anchorID), ["showcase-title"])
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
