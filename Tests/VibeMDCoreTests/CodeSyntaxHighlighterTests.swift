import XCTest
@testable import VibeMDCore

final class CodeSyntaxHighlighterTests: XCTestCase {
    private let highlighter = CodeSyntaxHighlighter()

    func testSwiftPresentationRunsExposeSemanticTokenKinds() {
        let runs = highlighter.presentationRuns(
            code: """
            struct Theme {
                let title = "VibeMD"
                // comment
            }
            """,
            language: "swift"
        )

        let kinds = Set(runs.compactMap(\.kind))
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.type))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.comment))
    }

    func testHighlightedHTMLUsesThemeSyntaxClasses() {
        let code = """
        struct Theme {
            let title = "VibeMD"
            // comment
        }
        """

        let html = highlighter.highlightedHTML(code: code, language: "swift")
        XCTAssertTrue(html.contains("<span class=\"cm-keyword\">"))
        XCTAssertTrue(html.contains("<span class=\"cm-def\">"))
        XCTAssertTrue(html.contains("cm-string"))
        XCTAssertTrue(html.contains("cm-comment"))
    }

    func testUntaggedCodeProducesSinglePlainRun() {
        let runs = highlighter.presentationRuns(code: "plain code", language: nil)

        XCTAssertEqual(runs.count, 1)
        XCTAssertNil(runs.first?.kind)
    }

    func testShellAliasesNormalizeToBashRules() {
        let shellKinds = Set(
            highlighter.presentationRuns(
                code: "export PATH=\"$HOME/bin\"\n# note",
                language: "shell"
            ).compactMap(\.kind)
        )
        let bashKinds = Set(
            highlighter.presentationRuns(
                code: "export PATH=\"$HOME/bin\"\n# note",
                language: "bash"
            ).compactMap(\.kind)
        )

        XCTAssertEqual(shellKinds, bashKinds)
        XCTAssertTrue(shellKinds.contains(.keyword))
        XCTAssertTrue(shellKinds.contains(.string))
        XCTAssertTrue(shellKinds.contains(.comment))
    }

    func testJSONRulesHighlightKeysStringsNumbersAndKeywords() {
        let kinds = Set(
            highlighter.presentationRuns(
                code: """
                {"title":"VibeMD","count":2,"enabled":true,"empty":null}
                """,
                language: "json"
            ).compactMap(\.kind)
        )

        XCTAssertTrue(kinds.contains(.type))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.number))
        XCTAssertTrue(kinds.contains(.keyword))
    }

    func testYAMLRulesHighlightKeysStringsNumbersKeywordsAndComments() {
        let kinds = Set(
            highlighter.presentationRuns(
                code: """
                title: "VibeMD"
                retries: 3
                enabled: true
                # comment
                """,
                language: "yml"
            ).compactMap(\.kind)
        )

        XCTAssertTrue(kinds.contains(.type))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.number))
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.comment))
    }

    func testMarkdownRulesHighlightHeadersCodeAndComments() {
        let kinds = Set(
            highlighter.presentationRuns(
                code: """
                # Heading
                `inline`
                <!-- note -->
                """,
                language: "markdown"
            ).compactMap(\.kind)
        )

        XCTAssertTrue(kinds.contains(.type))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.comment))
    }

    func testUnknownLanguageFallsBackToPlainRuns() {
        let runs = highlighter.presentationRuns(code: "SELECT * FROM table", language: "sql")

        XCTAssertEqual(runs.count, 1)
        XCTAssertNil(runs.first?.kind)
    }
}
