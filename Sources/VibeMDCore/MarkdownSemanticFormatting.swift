import Foundation
import Markdown

enum MarkdownSemanticSupport {
    static func calloutDefinition(for directive: BlockDirective) -> MarkdownCalloutDefinition? {
        guard let kind = MarkdownCalloutKind(directiveName: directive.name) else {
            return nil
        }

        let label = calloutTitleOverride(for: directive) ?? defaultCalloutLabel(for: directive.name)
        return MarkdownCalloutDefinition(kind: kind, label: label)
    }

    static func calloutTitleOverride(for directive: BlockDirective) -> String? {
        let arguments = directive.argumentText.parseNameValueArguments()
        guard
            let titleArgument = arguments.first(where: {
                $0.name.compare("title", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }),
            !titleArgument.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return titleArgument.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func defaultCalloutLabel(for directiveName: String) -> String {
        directiveName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .capitalized
    }

    static func inlineAttributeClassName(from attributes: InlineAttributes) -> String? {
        let payload = attributes.attributes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return nil
        }

        let wrappedPayload = payload.hasPrefix("{") ? payload : "{\(payload)}"
        guard let data = wrappedPayload.data(using: .utf8) else {
            return nil
        }

        struct ParsedAttributes: Decodable {
            let `class`: String?
        }

        let decoder = JSONDecoder()
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) {
            decoder.allowsJSON5 = true
        }
        #elseif compiler(>=6.0)
        decoder.allowsJSON5 = true
        #endif

        guard
            let parsed = try? decoder.decode(ParsedAttributes.self, from: data),
            let className = parsed.class?.trimmingCharacters(in: .whitespacesAndNewlines),
            !className.isEmpty
        else {
            return nil
        }

        return className
    }

    static func inlineHTMLTransition(from source: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: #"^<\s*/?\s*([A-Za-z0-9]+)[^>]*>$"#),
            let match = regex.firstMatch(
                in: source,
                options: [],
                range: NSRange(location: 0, length: source.utf16.count)
            ),
            let nameRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return source[nameRange].lowercased()
    }

    static func strippedHTMLText(from source: String) -> String {
        source
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MarkdownCalloutDefinition: Equatable {
    let kind: MarkdownCalloutKind
    let label: String
}

enum MarkdownCalloutKind: String, Equatable {
    case note
    case tip
    case important
    case warning
    case caution

    init?(directiveName: String) {
        switch directiveName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "note", "info":
            self = .note
        case "tip":
            self = .tip
        case "important":
            self = .important
        case "warning":
            self = .warning
        case "caution":
            self = .caution
        default:
            return nil
        }
    }

    var cssClassName: String {
        "md-callout-\(rawValue)"
    }
}
