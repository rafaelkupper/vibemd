import XCTest
@testable import VibeMDCore

final class CodeSyntaxHighlighterTests: XCTestCase {
    private let highlighter = CodeSyntaxHighlighter()

    func testSwiftPresentationRunsExposeSemanticTokenKinds() {
        let runs = highlighter.presentationRuns(
            code: """
            struct Theme {
                let title = "VibeMD"
                func render() {}
                // comment
            }
            """,
            language: "swift"
        )

        let kinds = Set(runs.compactMap(\.kind))
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.type))
        XCTAssertTrue(kinds.contains(.string))
        XCTAssertTrue(kinds.contains(.function))
        XCTAssertTrue(kinds.contains(.comment))
    }

    func testHighlightedHTMLUsesExpandedThemeSyntaxClasses() {
        let code = """
        @memoize
        const renderCard = (props) => props.title
        """

        let html = highlighter.highlightedHTML(code: code, language: "typescript")
        XCTAssertTrue(html.contains("<span class=\"cm-atom\">"))
        XCTAssertTrue(html.contains("<span class=\"cm-keyword\">"))
        XCTAssertTrue(html.contains("<span class=\"cm-variable-2\">"))
        XCTAssertTrue(html.contains("<span class=\"cm-property\">"))
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

    func testAdditionalLanguagesExposeExpectedSemanticTokenKinds() {
        struct Sample {
            let language: String
            let code: String
            let expectedKinds: Set<CodeSyntaxHighlighter.TokenKind>
        }

        let samples: [Sample] = [
            Sample(
                language: "go",
                code: """
                package main
                type Reader struct { title string }
                func renderCard(value Reader) string {
                    return `ok`
                }
                // comment
                """,
                expectedKinds: [.keyword, .type, .function, .string, .comment]
            ),
            Sample(
                language: "ruby",
                code: """
                class Reader
                  def render_card
                    @title = "VibeMD" # comment
                  end
                end
                """,
                expectedKinds: [.keyword, .type, .function, .member, .string, .comment]
            ),
            Sample(
                language: "python",
                code: """
                class Reader:
                    @cached_property
                    def render(self):
                        return self.title
                """,
                expectedKinds: [.keyword, .type, .function, .member, .meta]
            ),
            Sample(
                language: "elixir",
                code: """
                defmodule Reader do
                  def render_card(user) do
                    user.title
                    :ok
                  end
                end
                """,
                expectedKinds: [.keyword, .type, .function, .member, .meta]
            ),
            Sample(
                language: "javascript",
                code: """
                class Reader {}
                const renderCard = (props) => props.title
                """,
                expectedKinds: [.keyword, .type, .function, .member]
            ),
            Sample(
                language: "typescript",
                code: """
                interface Props { title: string }
                const renderCard = (props: Props) => props.title
                """,
                expectedKinds: [.keyword, .type, .function, .member]
            ),
            Sample(
                language: "php",
                code: """
                class Reader {
                    public function renderCard() {
                        return $this->title;
                    }
                }
                """,
                expectedKinds: [.keyword, .type, .function, .member]
            ),
            Sample(
                language: "c",
                code: """
                #include <stdio.h>
                int render_card(struct reader *value) {
                    return value->title[0];
                }
                """,
                expectedKinds: [.meta, .type, .function, .member]
            ),
            Sample(
                language: "cpp",
                code: """
                #include <string>
                class Reader {};
                std::string render_card(Reader* value) {
                    return value->title;
                }
                """,
                expectedKinds: [.meta, .keyword, .type, .function, .member]
            ),
            Sample(
                language: "rust",
                code: """
                #[derive(Debug)]
                struct Reader { title: String }
                fn render_card(reader: Reader) -> String {
                    reader.title
                }
                """,
                expectedKinds: [.meta, .keyword, .type, .function, .member]
            ),
            Sample(
                language: "zig",
                code: """
                const Reader = struct { title: []const u8 };
                fn renderCard(reader: Reader) []const u8 {
                    return reader.title;
                }
                const standard = @import("std");
                """,
                expectedKinds: [.keyword, .type, .function, .member, .meta, .string]
            ),
            Sample(
                language: "haskell",
                code: """
                {-# LANGUAGE OverloadedStrings #-}
                data Reader = Reader
                renderCard reader = reader
                """,
                expectedKinds: [.meta, .keyword, .type, .function]
            ),
            Sample(
                language: "java",
                code: """
                @Override
                class Reader {
                    String renderCard(Reader value) {
                        return value.title;
                    }
                }
                """,
                expectedKinds: [.meta, .keyword, .type, .function, .member]
            ),
        ]

        for sample in samples {
            let kinds = Set(highlighter.presentationRuns(code: sample.code, language: sample.language).compactMap(\.kind))
            XCTAssertTrue(sample.expectedKinds.isSubset(of: kinds), "Missing expected kinds for \(sample.language): \(sample.expectedKinds.subtracting(kinds))")
        }
    }

    func testBroadLanguageAliasesNormalizeToCanonicalRuleSets() {
        assertAlias("golang", canonical: "go", code: "func renderCard() string { return `ok` }")
        assertAlias("rb", canonical: "ruby", code: "def render_card\n  @title = \"VibeMD\"\nend")
        assertAlias("py", canonical: "python", code: "@cached_property\ndef render(self):\n    return self.title")
        assertAlias("jsx", canonical: "javascript", code: "const renderCard = (props) => props.title")
        assertAlias("tsx", canonical: "typescript", code: "interface Props { title: string }\nconst renderCard = (props: Props) => props.title")
        assertAlias("rs", canonical: "rust", code: "#[derive(Debug)]\nfn render_card() {}")
        assertAlias("c++", canonical: "cpp", code: "#include <string>\nstd::string render_card();")
        assertAlias("hpp", canonical: "cpp", code: "#include <string>\nstd::string render_card();")
        assertAlias("hs", canonical: "haskell", code: "{-# LANGUAGE OverloadedStrings #-}\nrenderCard value = value")
        assertAlias("exs", canonical: "elixir", code: "defmodule Reader do\n  def render_card, do: :ok\nend")
    }

    func testUnknownLanguageFallsBackToPlainRuns() {
        let runs = highlighter.presentationRuns(code: "SELECT * FROM table", language: "sql")

        XCTAssertEqual(runs.count, 1)
        XCTAssertNil(runs.first?.kind)
    }

    private func assertAlias(_ alias: String, canonical: String, code: String) {
        let aliasKinds = Set(highlighter.presentationRuns(code: code, language: alias).compactMap(\.kind))
        let canonicalKinds = Set(highlighter.presentationRuns(code: code, language: canonical).compactMap(\.kind))
        XCTAssertEqual(aliasKinds, canonicalKinds, "Alias \(alias) should normalize to \(canonical)")
    }
}
