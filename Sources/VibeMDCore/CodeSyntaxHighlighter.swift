import Foundation

struct CodeSyntaxHighlighter {
    enum TokenKind: String, CaseIterable {
        case keyword
        case type
        case string
        case number
        case comment
        case function
        case member
        case meta
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
        case function
        case member
        case meta
    }

    private struct HighlightRule {
        let pattern: String
        let options: NSRegularExpression.Options
        let color: TokenColor
        let captureGroup: Int?
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
        let stringLength = (code as NSString).length
        guard let normalizedLanguage = normalized(language), !code.isEmpty else {
            return [PresentationRun(range: NSRange(location: 0, length: stringLength), kind: nil)]
        }

        var kinds = Array<TokenKind?>(repeating: nil, count: stringLength)
        let fullRange = NSRange(location: 0, length: stringLength)

        for rule in rules(for: normalizedLanguage) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }

            regex.enumerateMatches(in: code, options: [], range: fullRange) { match, _, _ in
                guard let match else {
                    return
                }

                let targetRange: NSRange
                if let captureGroup = rule.captureGroup {
                    let captureRange = match.range(at: captureGroup)
                    guard captureRange.location != NSNotFound, captureRange.length > 0 else {
                        return
                    }
                    targetRange = captureRange
                } else {
                    targetRange = match.range
                }

                let kind = tokenKind(for: rule.color)
                let upperBound = NSMaxRange(targetRange)
                guard targetRange.location < upperBound else {
                    return
                }

                for index in targetRange.location..<upperBound where index < kinds.count {
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
        case "golang":
            return "go"
        case "rb":
            return "ruby"
        case "py":
            return "python"
        case "ex", "exs":
            return "elixir"
        case "js", "jsx", "mjs", "cjs":
            return "javascript"
        case "ts", "tsx":
            return "typescript"
        case "c++", "cc", "cxx", "hpp", "hh", "hxx":
            return "cpp"
        case "h":
            return "c"
        case "rs":
            return "rust"
        case "hs":
            return "haskell"
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
        case "go":
            goRules
        case "ruby":
            rubyRules
        case "python":
            pythonRules
        case "elixir":
            elixirRules
        case "javascript":
            javaScriptRules
        case "typescript":
            typeScriptRules
        case "php":
            phpRules
        case "c":
            cRules
        case "cpp":
            cppRules
        case "rust":
            rustRules
        case "zig":
            zigRules
        case "haskell":
            haskellRules
        case "java":
            javaRules
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
        case .function:
            .function
        case .member:
            .member
        case .meta:
            .meta
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
        case .function:
            return "cm-variable-2"
        case .member:
            return "cm-property"
        case .meta:
            return "cm-atom"
        }
    }

    private func rule(
        _ pattern: String,
        options: NSRegularExpression.Options = [],
        color: TokenColor,
        captureGroup: Int? = nil
    ) -> HighlightRule {
        HighlightRule(
            pattern: pattern,
            options: options,
            color: color,
            captureGroup: captureGroup
        )
    }

    private func wordRule(_ words: [String], color: TokenColor) -> HighlightRule {
        rule(#"\b(?:\#(escapedAlternation(words)))\b"#, color: color)
    }

    private func escapedAlternation(_ words: [String]) -> String {
        words
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }

    private var numberRule: HighlightRule {
        rule(#"\b(?:0x[0-9A-Fa-f]+|0b[01]+|0o[0-7]+|\d+(?:\.\d+)?)\b"#, color: .number)
    }

    private var quotedStringRule: HighlightRule {
        rule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: .string)
    }

    private var quotedAndBacktickStringRule: HighlightRule {
        rule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`[^`]*`"#, color: .string)
    }

    private var pythonStringRule: HighlightRule {
        rule(##"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"##, color: .string)
    }

    private var slashCommentRule: HighlightRule {
        rule(#"//.*$|/\*[\s\S]*?\*/"#, options: [.anchorsMatchLines], color: .comment)
    }

    private var hashCommentRule: HighlightRule {
        rule(#"#.*$"#, options: [.anchorsMatchLines], color: .comment)
    }

    private var haskellCommentRule: HighlightRule {
        rule(#"--.*$|\{-(?!#)[\s\S]*?-\}"#, options: [.anchorsMatchLines], color: .comment)
    }

    private var memberAccessRule: HighlightRule {
        rule(#"(?:\.|->)\s*([A-Za-z_][A-Za-z0-9_]*)"#, color: .member, captureGroup: 1)
    }

    private var phpMemberAccessRule: HighlightRule {
        rule(#"(?:->|::)\s*([A-Za-z_][A-Za-z0-9_]*)"#, color: .member, captureGroup: 1)
    }

    private var annotationRule: HighlightRule {
        rule(#"@[A-Za-z_][A-Za-z0-9_\.]*"#, color: .meta)
    }

    private var cPreprocessorRule: HighlightRule {
        rule(#"^\s*#\s*(?:include|define|if|ifdef|ifndef|elif|else|endif|pragma|error|warning)\b.*$"#, options: [.anchorsMatchLines], color: .meta)
    }

    private var rustAttributeRule: HighlightRule {
        rule(#"#\!?\[[^\]]+\]"#, color: .meta)
    }

    private var elixirAtomRule: HighlightRule {
        rule(#":[A-Za-z_][A-Za-z0-9_!?]*"#, color: .meta)
    }

    private var haskellPragmaRule: HighlightRule {
        rule(#"\{\-#[\s\S]*?#-\}"#, color: .meta)
    }

    private var swiftRules: [HighlightRule] {
        [
            wordRule([
                "associatedtype", "actor", "as", "async", "await", "break", "case", "catch", "class", "continue",
                "default", "defer", "deinit", "do", "else", "enum", "extension", "false", "fileprivate", "for",
                "func", "guard", "if", "import", "in", "init", "inout", "internal", "let", "nil", "nonisolated",
                "open", "private", "protocol", "public", "repeat", "return", "static", "struct", "subscript",
                "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while"
            ], color: .keyword),
            rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, color: .type),
            rule(#"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedStringRule,
            rule(#"^#(?:if|elseif|else|endif|available|warning|error)\b.*$"#, options: [.anchorsMatchLines], color: .meta),
            slashCommentRule,
        ]
    }

    private var shellRules: [HighlightRule] {
        [
            wordRule([
                "case", "do", "done", "elif", "else", "esac", "exit", "export", "fi", "for", "function",
                "if", "in", "local", "return", "source", "then", "while"
            ], color: .keyword),
            rule(#"\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]+\}"#, color: .type),
            quotedStringRule,
            hashCommentRule,
        ]
    }

    private var jsonRules: [HighlightRule] {
        [
            rule(#""(?:\\.|[^"\\])*"\s*:"# , color: .type),
            quotedStringRule,
            numberRule,
            wordRule(["true", "false", "null"], color: .keyword),
        ]
    }

    private var yamlRules: [HighlightRule] {
        [
            rule(#"^\s*[-?]?\s*[A-Za-z0-9_-]+\s*:"# , options: [.anchorsMatchLines], color: .type),
            quotedStringRule,
            numberRule,
            wordRule(["true", "false", "null", "yes", "no", "on", "off"], color: .keyword),
            hashCommentRule,
        ]
    }

    private var markdownRules: [HighlightRule] {
        [
            rule(#"^#{1,6}\s.*$"#, options: [.anchorsMatchLines], color: .type),
            rule(#"^```.*$"#, options: [.anchorsMatchLines], color: .keyword),
            rule(#"`[^`]+`"#, color: .string),
            rule(#"<!--[\s\S]*?-->"#, color: .comment),
        ]
    }

    private var goRules: [HighlightRule] {
        [
            wordRule([
                "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
                "for", "func", "go", "goto", "if", "import", "interface", "package", "range", "return",
                "select", "struct", "switch", "type", "var"
            ], color: .keyword),
            wordRule(["any", "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64"], color: .type),
            rule(#"\btype\s+([A-Z][A-Za-z0-9_]*)\b"#, color: .type, captureGroup: 1),
            rule(#"\bfunc(?:\s*\([^)]*\))?\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedAndBacktickStringRule,
            slashCommentRule,
        ]
    }

    private var rubyRules: [HighlightRule] {
        [
            wordRule([
                "BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "defined?",
                "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
                "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then",
                "true", "undef", "unless", "until", "when", "while", "yield"
            ], color: .keyword),
            rule(#"\b(?:class|module)\s+([A-Z][A-Za-z0-9_:]*)"#, color: .type, captureGroup: 1),
            rule(#"\bdef\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_!?=]*)"#, color: .function, captureGroup: 1),
            rule(#"(?:@@?[A-Za-z_][A-Za-z0-9_]*|@[A-Za-z_][A-Za-z0-9_]*|\$[A-Za-z_][A-Za-z0-9_]*)"#, color: .member),
            rule(#":[A-Za-z_][A-Za-z0-9_!?=]*"#, color: .meta),
            numberRule,
            quotedStringRule,
            hashCommentRule,
        ]
    }

    private var pythonRules: [HighlightRule] {
        [
            wordRule([
                "and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del",
                "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import",
                "in", "is", "lambda", "match", "None", "nonlocal", "not", "or", "pass", "raise", "return",
                "True", "try", "while", "with", "yield"
            ], color: .keyword),
            rule(#"\bclass\s+([A-Z][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"\bdef\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: .function, captureGroup: 1),
            memberAccessRule,
            annotationRule,
            numberRule,
            pythonStringRule,
            hashCommentRule,
        ]
    }

    private var elixirRules: [HighlightRule] {
        [
            wordRule([
                "after", "case", "catch", "cond", "def", "defdelegate", "defexception", "defguard",
                "defguardp", "defimpl", "defmacro", "defmacrop", "defmodule", "defoverridable", "defp",
                "defprotocol", "defstruct", "do", "else", "end", "false", "fn", "for", "if", "import",
                "in", "nil", "quote", "raise", "receive", "require", "rescue", "reraise", "super", "throw",
                "true", "try", "unless", "unquote", "use", "when", "with"
            ], color: .keyword),
            rule(#"\bdefmodule\s+([A-Z][A-Za-z0-9_\.]*)"#, color: .type, captureGroup: 1),
            rule(#"\b(?:def|defp|defmacro|defmacrop)\s+([A-Za-z_][A-Za-z0-9_!?]*)"#, color: .function, captureGroup: 1),
            memberAccessRule,
            elixirAtomRule,
            numberRule,
            quotedStringRule,
            hashCommentRule,
        ]
    }

    private var javaScriptRules: [HighlightRule] {
        [
            wordRule([
                "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
                "delete", "do", "else", "export", "extends", "false", "finally", "for", "function", "if",
                "import", "in", "instanceof", "let", "new", "null", "of", "return", "super", "switch",
                "this", "throw", "true", "try", "typeof", "var", "void", "while", "yield"
            ], color: .keyword),
            rule(#"\bclass\s+([A-Z][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, color: .type),
            rule(#"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\b"#, color: .member, captureGroup: 1),
            rule(#"\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, color: .function, captureGroup: 1),
            rule(#"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)\s*=>"#, color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedAndBacktickStringRule,
            annotationRule,
            slashCommentRule,
        ]
    }

    private var typeScriptRules: [HighlightRule] {
        [
            wordRule([
                "abstract", "any", "as", "async", "await", "bigint", "boolean", "break", "case", "catch",
                "class", "const", "constructor", "continue", "declare", "default", "delete", "do", "else",
                "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements",
                "import", "in", "infer", "instanceof", "interface", "is", "keyof", "let", "module", "namespace",
                "never", "new", "null", "number", "object", "override", "private", "protected", "public",
                "readonly", "return", "satisfies", "static", "string", "super", "switch", "symbol", "this",
                "throw", "true", "try", "type", "typeof", "undefined", "unknown", "var", "void", "while",
                "yield"
            ], color: .keyword),
            rule(#"\b(?:class|interface|type|enum|namespace)\s+([A-Z][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"\b[A-Z][A-Za-z0-9_]*\b"#, color: .type),
            rule(#"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\b"#, color: .member, captureGroup: 1),
            rule(#"\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, color: .function, captureGroup: 1),
            rule(#"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)\s*=>"#, color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedAndBacktickStringRule,
            annotationRule,
            slashCommentRule,
        ]
    }

    private var phpRules: [HighlightRule] {
        [
            wordRule([
                "abstract", "as", "break", "case", "catch", "class", "clone", "const", "continue", "declare",
                "default", "do", "echo", "else", "elseif", "enum", "extends", "false", "final", "finally",
                "fn", "for", "foreach", "function", "if", "implements", "include", "include_once", "instanceof",
                "interface", "match", "namespace", "new", "null", "private", "protected", "public", "readonly",
                "require", "require_once", "return", "static", "switch", "throw", "trait", "true", "try",
                "use", "while"
            ], color: .keyword),
            rule(#"\b(?:class|interface|trait|enum)\s+([A-Z][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: .function, captureGroup: 1),
            rule(#"\$[A-Za-z_][A-Za-z0-9_]*"#, color: .member),
            phpMemberAccessRule,
            numberRule,
            quotedStringRule,
            rule(#"#\[[^\]]+\]|@[A-Za-z_\\][A-Za-z0-9_\\]*"#, color: .meta),
            rule(#"//.*$|#.*$|/\*[\s\S]*?\*/"#, options: [.anchorsMatchLines], color: .comment),
        ]
    }

    private var cRules: [HighlightRule] {
        [
            wordRule([
                "auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern",
                "for", "goto", "if", "inline", "register", "restrict", "return", "sizeof", "static",
                "struct", "switch", "typedef", "union", "volatile", "while"
            ], color: .keyword),
            wordRule(["bool", "char", "double", "FILE", "float", "int", "long", "short", "signed", "size_t", "ssize_t", "unsigned", "void"], color: .type),
            rule(#"\b(?:struct|enum|union|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"^\s*(?:static\s+|inline\s+|extern\s+)?(?:[A-Za-z_][A-Za-z0-9_]*\s+)+([A-Za-z_][A-Za-z0-9_]*)\s*\("#, options: [.anchorsMatchLines], color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedStringRule,
            cPreprocessorRule,
            slashCommentRule,
        ]
    }

    private var cppRules: [HighlightRule] {
        [
            wordRule([
                "alignas", "alignof", "asm", "auto", "break", "case", "catch", "class", "const", "constexpr",
                "consteval", "constinit", "continue", "co_await", "co_return", "co_yield", "decltype", "default",
                "delete", "do", "else", "enum", "explicit", "export", "extern", "false", "final", "for",
                "friend", "goto", "if", "inline", "mutable", "namespace", "new", "noexcept", "nullptr", "operator",
                "override", "private", "protected", "public", "register", "return", "sizeof", "static", "struct",
                "switch", "template", "this", "throw", "true", "try", "typedef", "typename", "union", "using",
                "virtual", "volatile", "while"
            ], color: .keyword),
            wordRule(["bool", "char", "double", "float", "int", "long", "short", "signed", "size_t", "std", "string", "unsigned", "void"], color: .type),
            rule(#"\b(?:class|struct|enum|namespace|typename)\s+([A-Z][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"^\s*(?:template\s*<[^>]+>\s*)?(?:(?:inline|virtual|static|constexpr|friend|explicit)\s+)*(?:[A-Za-z_][A-Za-z0-9_:<>\*&\s]+)\s+([A-Za-z_~][A-Za-z0-9_]*)\s*\("#, options: [.anchorsMatchLines], color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedStringRule,
            cPreprocessorRule,
            slashCommentRule,
        ]
    }

    private var rustRules: [HighlightRule] {
        [
            wordRule([
                "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
                "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub",
                "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
                "use", "where", "while"
            ], color: .keyword),
            wordRule(["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "String", "u8", "u16", "u32", "u64", "u128", "usize"], color: .type),
            rule(#"\b(?:struct|enum|trait|type|union|impl)\s+([A-Z][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedStringRule,
            rustAttributeRule,
            rule(#"\b([A-Za-z_][A-Za-z0-9_]*)!"#, color: .meta, captureGroup: 1),
            slashCommentRule,
        ]
    }

    private var zigRules: [HighlightRule] {
        [
            wordRule([
                "addrspace", "align", "allowzero", "and", "anyframe", "asm", "async", "await", "break",
                "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error", "export",
                "extern", "false", "fn", "for", "if", "inline", "linksection", "noalias", "nosuspend", "null",
                "opaque", "or", "orelse", "packed", "pub", "resume", "return", "struct", "suspend", "switch",
                "test", "threadlocal", "true", "try", "union", "unreachable", "usingnamespace", "var", "volatile",
                "while"
            ], color: .keyword),
            wordRule(["anytype", "bool", "f16", "f32", "f64", "f80", "f128", "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "void"], color: .type),
            rule(#"\b(?:const|var)\s+([A-Z][A-Za-z0-9_]*)\b"#, color: .type, captureGroup: 1),
            rule(#"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)"#, color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedStringRule,
            rule(#"@[A-Za-z_][A-Za-z0-9_]*"#, color: .meta),
            slashCommentRule,
        ]
    }

    private var haskellRules: [HighlightRule] {
        [
            wordRule([
                "case", "class", "data", "default", "deriving", "do", "else", "if", "import", "in", "infix",
                "infixl", "infixr", "instance", "let", "module", "newtype", "of", "then", "type", "where"
            ], color: .keyword),
            rule(#"\b(?:data|newtype|type|class|instance)\s+([A-Z][A-Za-z0-9_']*)"#, color: .type, captureGroup: 1),
            rule(#"\b[A-Z][A-Za-z0-9_']*\b"#, color: .type),
            rule(#"^\s*(?!data\b|newtype\b|type\b|class\b|instance\b|module\b|import\b|if\b|then\b|else\b|case\b|let\b|in\b|where\b|do\b)([a-z][A-Za-z0-9_']*)\b(?:(?:\s+[A-Za-z_][A-Za-z0-9_']*)*\s*=|\s*::)"#, options: [.anchorsMatchLines], color: .function, captureGroup: 1),
            numberRule,
            quotedStringRule,
            haskellPragmaRule,
            haskellCommentRule,
        ]
    }

    private var javaRules: [HighlightRule] {
        [
            wordRule([
                "abstract", "assert", "break", "case", "catch", "class", "continue", "default", "do", "else",
                "enum", "extends", "false", "final", "finally", "for", "if", "implements", "import", "instanceof",
                "interface", "native", "new", "null", "package", "private", "protected", "public", "record",
                "return", "sealed", "static", "super", "switch", "synchronized", "this", "throw", "throws",
                "transient", "true", "try", "volatile", "while"
            ], color: .keyword),
            wordRule(["boolean", "byte", "char", "double", "float", "int", "Integer", "List", "long", "Map", "Object", "short", "String", "void"], color: .type),
            rule(#"\b(?:class|interface|enum|record)\s+([A-Z][A-Za-z0-9_]*)"#, color: .type, captureGroup: 1),
            rule(#"^\s*(?:(?:public|private|protected|static|final|abstract|synchronized|native|default|strictfp)\s+)*(?:[A-Za-z_][A-Za-z0-9_<>\[\]]*\s+)+([A-Za-z_][A-Za-z0-9_]*)\s*\("#, options: [.anchorsMatchLines], color: .function, captureGroup: 1),
            memberAccessRule,
            numberRule,
            quotedStringRule,
            annotationRule,
            slashCommentRule,
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
