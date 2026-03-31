import Foundation
import Markdown

public enum DocumentStatisticKind: String, CaseIterable, Equatable, Sendable {
    case words
    case minutes
    case lines
    case characters

    public var title: String {
        switch self {
        case .words:
            "Words"
        case .minutes:
            "Minutes"
        case .lines:
            "Lines"
        case .characters:
            "Characters"
        }
    }

    fileprivate func displayTitle(for value: Int) -> String {
        if value == 1 {
            switch self {
            case .words:
                return "Word"
            case .minutes:
                return "Minute"
            case .lines:
                return "Line"
            case .characters:
                return "Character"
            }
        }

        return title
    }
}

public struct DocumentStatistics: Equatable, Sendable {
    public static let zero = DocumentStatistics(words: 0, minutes: 0, lines: 0, characters: 0)

    public let words: Int
    public let minutes: Int
    public let lines: Int
    public let characters: Int

    public init(words: Int, minutes: Int, lines: Int, characters: Int) {
        self.words = words
        self.minutes = minutes
        self.lines = lines
        self.characters = characters
    }

    public func value(for kind: DocumentStatisticKind) -> Int {
        switch kind {
        case .words:
            words
        case .minutes:
            minutes
        case .lines:
            lines
        case .characters:
            characters
        }
    }

    public func displayText(for kind: DocumentStatisticKind, locale: Locale = .current) -> String {
        let value = value(for: kind)
        let formattedValue = NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        return "\(formattedValue) \(kind.displayTitle(for: value))"
    }
}

enum RenderedTextDocumentStatistics {
    static func renderedText(from document: MarkdownDocument) -> String {
        var extractor = RenderedTextExtractor()
        return extractor.visit(document.ast).normalizedRenderedText
    }

    static func statistics(from document: MarkdownDocument) -> DocumentStatistics {
        statistics(fromRenderedText: renderedText(from: document))
    }

    static func statistics(fromRenderedText text: String) -> DocumentStatistics {
        let normalizedText = text.normalizedRenderedText
        let words = wordCount(in: normalizedText)
        let lines = logicalLineCount(in: normalizedText)
        let characters = normalizedText.count
        let minutes = words == 0 ? 0 : max(1, Int(ceil(Double(words) / 200.0)))

        return DocumentStatistics(
            words: words,
            minutes: minutes,
            lines: lines,
            characters: characters
        )
    }

    private static func wordCount(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .localized]
        ) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func logicalLineCount(in text: String) -> Int {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }
}

private struct RenderedTextExtractor: MarkupVisitor {
    typealias Result = String

    mutating func visit(_ markup: Markup) -> String {
        markup.accept(&self)
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        if markup is BlockMarkup {
            return joinBlockChildren(of: markup)
        }

        return joinInlineChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        joinBlockChildren(of: document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        joinInlineChildren(of: paragraph)
    }

    mutating func visitText(_ text: Text) -> String {
        text.string
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        " "
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "\n"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        joinInlineChildren(of: strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        joinInlineChildren(of: emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        joinInlineChildren(of: strikethrough)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        joinInlineChildren(of: heading)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        inlineCode.code
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        symbolLink.destination ?? ""
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> String {
        joinInlineChildren(of: attributes)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        codeBlock.code.trimmingCharacters(in: .newlines)
    }

    mutating func visitLink(_ link: Link) -> String {
        joinInlineChildren(of: link)
    }

    mutating func visitImage(_ image: Image) -> String {
        ""
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        joinBlockChildren(of: blockQuote)
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        joinChildren(of: unorderedList, separator: "\n")
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        joinChildren(of: orderedList, separator: "\n")
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        joinBlockChildren(of: listItem, separator: "\n").strippingTaskListPrefix
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        ""
    }

    mutating func visitTable(_ table: Table) -> String {
        joinChildren(of: table, separator: "\n")
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        joinChildren(of: tableHead, separator: "\n")
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        joinChildren(of: tableBody, separator: "\n")
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        joinChildren(of: tableRow, separator: " ")
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        joinChildren(of: tableCell, separator: " ")
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        MarkdownSemanticSupport.strippedHTMLText(from: html.format())
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        let source = inlineHTML.format()
        if MarkdownSemanticSupport.inlineHTMLTransition(from: source) == "kbd" {
            return ""
        }
        return MarkdownSemanticSupport.strippedHTMLText(from: source)
    }

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> String {
        if let callout = MarkdownSemanticSupport.calloutDefinition(for: blockDirective) {
            let body = joinBlockChildren(of: blockDirective)
            return [callout.label, body]
                .map(\.normalizedRenderedText)
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        return blockDirective.format().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func joinInlineChildren(of markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    private mutating func joinBlockChildren(of markup: Markup, separator: String = "\n\n") -> String {
        joinChildren(of: markup, separator: separator)
    }

    private mutating func joinChildren(of markup: Markup, separator: String) -> String {
        markup.children
            .map { visit($0).normalizedRenderedText }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

}

private extension String {
    var normalizedRenderedText: String {
        let normalizedNewlines = self
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let collapsedHorizontalWhitespace = normalizedNewlines
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return collapsedHorizontalWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var strippingTaskListPrefix: String {
        let prefixes = ["[x] ", "[X] ", "[ ] "]
        for prefix in prefixes where hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}
