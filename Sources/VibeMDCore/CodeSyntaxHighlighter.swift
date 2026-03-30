import Foundation

struct CodeSyntaxHighlighter {
    enum TokenKind: String, CaseIterable {
        case keyword
        case type
        case string
        case number
        case comment
    }

    struct PresentationRun: Equatable {
        let range: NSRange
        let kind: TokenKind?
    }

    private enum TokenColor {
        case keyword
        case type
        case string
        case number
        case comment
    }

    private struct HighlightRule {
        let pattern: String
        let options: NSRegularExpression.Options
        let color: TokenColor
    }

    func highlightedHTML(code: String, language: String?) -> String {
        let runs = presentationRuns(code: code, language: language)
        guard !runs.isEmpty else {
            return ""
        }

        var output = ""
        let nsCode = code as NSString
        for run in runs where run.range.length > 0 {
            let substring = nsCode.substring(with: run.range).escapedHTML
            if let kind = run.kind, let tokenClass = cssClass(for: kind) {
                output += "<span class=\"\(tokenClass)\">\(substring)</span>"
            } else {
                output += substring
            }
        }

        return output
    }

    func presentationRuns(code: String, language: String?) -> [PresentationRun] {
        guard let normalizedLanguage = normalized(language), !code.isEmpty else {
            return [PresentationRun(range: NSRange(location: 0, length: (code as NSString).length), kind: nil)]
        }

        let stringLength = (code as NSString).length
        var kinds = Array<TokenKind?>(repeating: nil, count: stringLength)
        for rule in rules(for: normalizedLanguage) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }

            let fullRange = NSRange(location: 0, length: stringLength)
            regex.enumerateMatches(in: code, options: [], range: fullRange) { match, _, _ in
                guard let match else {
                    return
                }

                let kind = tokenKind(for: rule.color)
                let upperBound = NSMaxRange(match.range)
                guard match.range.location < upperBound else {
                    return
                }

                for index in match.range.location..<upperBound where index < kinds.count {
                    kinds[index] = kind
                }
            }
        }

        var runs: [PresentationRun] = []
        var currentKind: TokenKind?
        var currentLocation = 0

        for index in 0..<stringLength {
            let kind = kinds[index]
            if index == 0 {
                currentKind = kind
                currentLocation = 0
                continue
            }

            if kind != currentKind {
                runs.append(
                    PresentationRun(
                        range: NSRange(location: currentLocation, length: index - currentLocation),
                        kind: currentKind
                    )
                )
                currentKind = kind
                currentLocation = index
            }
        }

        runs.append(
            PresentationRun(
                range: NSRange(location: currentLocation, length: stringLength - currentLocation),
                kind: currentKind
            )
        )

        return runs
    }

    private func normalized(_ language: String?) -> String? {
        guard let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !trimmed.isEmpty else {
            return nil
        }

        switch trimmed {
        case "shell", "shellscript":
            return "bash"
        default:
            return trimmed
        }
    }

    private func rules(for language: String) -> [HighlightRule] {
        switch language {
        case "swift":
            swiftRules
        case "bash", "sh", "zsh":
            shellRules
        case "json":
            jsonRules
        case "yaml", "yml":
            yamlRules
        case "markdown", "md":
            markdownRules
        default:
            []
        }
    }

    private func tokenKind(for tokenColor: TokenColor) -> TokenKind {
        switch tokenColor {
        case .keyword:
            .keyword
        case .type:
            .type
        case .string:
            .string
        case .number:
            .number
        case .comment:
            .comment
        }
    }

    private func cssClass(for kind: TokenKind) -> String? {
        switch kind {
        case .keyword:
            return "cm-keyword"
        case .type:
            return "cm-def"
        case .string:
            return "cm-string"
        case .number:
            return "cm-number"
        case .comment:
            return "cm-comment"
        }
    }

    private var swiftRules: [HighlightRule] {
        [
            HighlightRule(
                pattern: #"\b(associatedtype|actor|as|async|await|break|case|catch|class|continue|default|defer|deinit|do|else|enum|extension|false|fileprivate|for|func|guard|if|import|in|init|inout|internal|let|nil|nonisolated|open|private|protocol|public|repeat|return|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while)\b"#,
                options: [],
                color: .keyword
            ),
            HighlightRule(
                pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#,
                options: [],
                color: .type
            ),
            HighlightRule(
                pattern: #"\b\d+(?:\.\d+)?\b"#,
                options: [],
                color: .number
            ),
            HighlightRule(
                pattern: #""(?:\\.|[^"\\])*""#,
                options: [],
                color: .string
            ),
            HighlightRule(
                pattern: #"//.*$|/\*[\s\S]*?\*/"#,
                options: [.anchorsMatchLines],
                color: .comment
            ),
        ]
    }

    private var shellRules: [HighlightRule] {
        [
            HighlightRule(
                pattern: #"\b(case|do|done|elif|else|esac|exit|export|fi|for|function|if|in|local|return|source|then|while)\b"#,
                options: [],
                color: .keyword
            ),
            HighlightRule(
                pattern: #"\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]+\}"#,
                options: [],
                color: .type
            ),
            HighlightRule(
                pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#,
                options: [],
                color: .string
            ),
            HighlightRule(
                pattern: #"#.*$"#,
                options: [.anchorsMatchLines],
                color: .comment
            ),
        ]
    }

    private var jsonRules: [HighlightRule] {
        [
            HighlightRule(
                pattern: #""(?:\\.|[^"\\])*"\s*:"#,
                options: [],
                color: .type
            ),
            HighlightRule(
                pattern: #""(?:\\.|[^"\\])*""#,
                options: [],
                color: .string
            ),
            HighlightRule(
                pattern: #"\b\d+(?:\.\d+)?\b"#,
                options: [],
                color: .number
            ),
            HighlightRule(
                pattern: #"\b(true|false|null)\b"#,
                options: [],
                color: .keyword
            ),
        ]
    }

    private var yamlRules: [HighlightRule] {
        [
            HighlightRule(
                pattern: #"^\s*[-?]?\s*[A-Za-z0-9_-]+\s*:"#,
                options: [.anchorsMatchLines],
                color: .type
            ),
            HighlightRule(
                pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#,
                options: [],
                color: .string
            ),
            HighlightRule(
                pattern: #"\b\d+(?:\.\d+)?\b"#,
                options: [],
                color: .number
            ),
            HighlightRule(
                pattern: #"\b(true|false|null|yes|no|on|off)\b"#,
                options: [],
                color: .keyword
            ),
            HighlightRule(
                pattern: #"#.*$"#,
                options: [.anchorsMatchLines],
                color: .comment
            ),
        ]
    }

    private var markdownRules: [HighlightRule] {
        [
            HighlightRule(
                pattern: #"^#{1,6}\s.*$"#,
                options: [.anchorsMatchLines],
                color: .type
            ),
            HighlightRule(
                pattern: #"^```.*$"#,
                options: [.anchorsMatchLines],
                color: .keyword
            ),
            HighlightRule(
                pattern: #"`[^`]+`"#,
                options: [],
                color: .string
            ),
            HighlightRule(
                pattern: #"<!--[\s\S]*?-->"#,
                options: [],
                color: .comment
            ),
        ]
    }
}

private extension String {
    var escapedHTML: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
