import Foundation
import Markdown

public struct DocumentSidebarEntry: Equatable, Sendable {
    public let fileURL: URL
    public let displayTitle: String
    public let previewText: String
    public let isCurrent: Bool
    public let isAvailable: Bool

    public init(
        fileURL: URL,
        displayTitle: String,
        previewText: String,
        isCurrent: Bool,
        isAvailable: Bool
    ) {
        self.fileURL = fileURL
        self.displayTitle = displayTitle
        self.previewText = previewText
        self.isCurrent = isCurrent
        self.isAvailable = isAvailable
    }
}

public struct DocumentOutlineItem: Equatable, Sendable {
    public let title: String
    public let level: Int
    public let anchorID: String

    public init(title: String, level: Int, anchorID: String) {
        self.title = title
        self.level = level
        self.anchorID = anchorID
    }
}

enum DocumentSidebarDataBuilder {
    static func sidebarEntries(
        from document: MarkdownDocument,
        assetResolver: AssetResolver,
        parser: MarkdownParser = MarkdownParser()
    ) -> [DocumentSidebarEntry] {
        guard let currentFileURL = normalizedCurrentFileURL(for: document) else {
            return []
        }

        var candidateURLs = [currentFileURL]
        var seen = Set([identity(for: currentFileURL)])
        let linkedURLs = MarkdownLinkCollector.collect(from: document, assetResolver: assetResolver)

        for linkedURL in linkedURLs {
            let normalizedURL = normalizedFileURL(linkedURL)
            let normalizedIdentity = identity(for: normalizedURL)
            if seen.insert(normalizedIdentity).inserted {
                candidateURLs.append(normalizedURL)
            }
        }

        let currentSummary = DocumentFileSummary(
            displayTitle: documentDisplayTitle(for: document, fallbackURL: currentFileURL),
            previewText: documentPreviewText(for: document)
        )

        let entries = candidateURLs.map { fileURL in
            if fileURL == currentFileURL {
                return DocumentSidebarEntry(
                    fileURL: fileURL,
                    displayTitle: currentSummary.displayTitle,
                    previewText: currentSummary.previewText,
                    isCurrent: true,
                    isAvailable: true
                )
            }

            guard
                let data = try? Data(contentsOf: fileURL),
                let source = decodedSource(from: data)
            else {
                return DocumentSidebarEntry(
                    fileURL: fileURL,
                    displayTitle: fileURL.deletingPathExtension().lastPathComponent,
                    previewText: "Unavailable",
                    isCurrent: false,
                    isAvailable: false
                )
            }

            let linkedDocument = parser.parse(source: source, baseURL: fileURL)
            return DocumentSidebarEntry(
                fileURL: fileURL,
                displayTitle: documentDisplayTitle(for: linkedDocument, fallbackURL: fileURL),
                previewText: documentPreviewText(for: linkedDocument),
                isCurrent: false,
                isAvailable: true
            )
        }

        return entries.sorted(by: sidebarEntryOrder(lhs:rhs:))
    }

    static func outlineItems(from document: MarkdownDocument) -> [DocumentOutlineItem] {
        HeadingOutlineCollector.collect(from: document)
    }

    private static func normalizedCurrentFileURL(for document: MarkdownDocument) -> URL? {
        guard let baseURL = document.baseURL, baseURL.isFileURL else {
            return nil
        }

        return normalizedFileURL(baseURL)
    }

    private static func normalizedFileURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path)
    }

    private static func identity(for url: URL) -> String {
        normalizedFileURL(url).path
    }

    private static func sidebarEntryOrder(lhs: DocumentSidebarEntry, rhs: DocumentSidebarEntry) -> Bool {
        let titleComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        let pathComparison = lhs.fileURL.lastPathComponent.localizedCaseInsensitiveCompare(rhs.fileURL.lastPathComponent)
        if pathComparison != .orderedSame {
            return pathComparison == .orderedAscending
        }

        return lhs.fileURL.path.localizedStandardCompare(rhs.fileURL.path) == .orderedAscending
    }

    private static func documentDisplayTitle(for document: MarkdownDocument, fallbackURL: URL) -> String {
        if let headingTitle = FirstHeadingTitleExtractor.extract(from: document), !headingTitle.isEmpty {
            return headingTitle
        }

        return fallbackURL.deletingPathExtension().lastPathComponent
    }

    private static func documentPreviewText(for document: MarkdownDocument) -> String {
        DocumentPreviewExtractor.extract(from: document)
    }

    private static func decodedSource(from data: Data) -> String? {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }

        return String(data: data, encoding: .unicode)
    }
}

private struct DocumentFileSummary {
    let displayTitle: String
    let previewText: String
}

private struct MarkdownLinkCollector: MarkupVisitor {
    typealias Result = [URL]

    let baseURL: URL?
    let assetResolver: AssetResolver

    static func collect(from document: MarkdownDocument, assetResolver: AssetResolver) -> [URL] {
        var collector = MarkdownLinkCollector(baseURL: document.baseURL, assetResolver: assetResolver)
        return collector.visit(document.ast)
    }

    mutating func visit(_ markup: Markup) -> [URL] {
        markup.accept(&self)
    }

    mutating func defaultVisit(_ markup: Markup) -> [URL] {
        markup.children.flatMap { visit($0) }
    }

    mutating func visitLink(_ link: Link) -> [URL] {
        guard
            let destination = link.destination,
            case .markdownFile(let url) = assetResolver.linkTarget(for: destination, relativeTo: baseURL)
        else {
            return defaultVisit(link)
        }

        return [url] + defaultVisit(link)
    }
}

private struct FirstHeadingTitleExtractor: MarkupVisitor {
    typealias Result = String?

    static func extract(from document: MarkdownDocument) -> String? {
        var extractor = FirstHeadingTitleExtractor()
        return extractor.visit(document.ast)?.normalizedPreviewText
    }

    mutating func visit(_ markup: Markup) -> String? {
        markup.accept(&self)
    }

    mutating func defaultVisit(_ markup: Markup) -> String? {
        for child in markup.children {
            if let title = visit(child), !title.isEmpty {
                return title
            }
        }
        return nil
    }

    mutating func visitHeading(_ heading: Heading) -> String? {
        guard heading.level == 1 else {
            return nil
        }

        return heading.plainText
    }
}

private struct DocumentPreviewExtractor: MarkupVisitor {
    typealias Result = String?

    static func extract(from document: MarkdownDocument) -> String {
        var extractor = DocumentPreviewExtractor()
        return extractor.visit(document.ast)?.previewSnippet ?? ""
    }

    mutating func visit(_ markup: Markup) -> String? {
        markup.accept(&self)
    }

    mutating func defaultVisit(_ markup: Markup) -> String? {
        for child in markup.children {
            if let preview = visit(child), !preview.isEmpty {
                return preview
            }
        }
        return nil
    }

    mutating func visitHeading(_ heading: Heading) -> String? {
        nil
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String? {
        paragraph.plainText.normalizedPreviewText
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String? {
        blockQuote.plainText.normalizedPreviewText
    }

    mutating func visitListItem(_ listItem: ListItem) -> String? {
        listItem.plainText.normalizedPreviewText.strippingTaskListPrefix
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String? {
        codeBlock.code.normalizedPreviewText
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String? {
        MarkdownSemanticSupport.strippedHTMLText(from: html.format()).normalizedPreviewText
    }

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> String? {
        if let callout = MarkdownSemanticSupport.calloutDefinition(for: blockDirective) {
            let body = blockDirective.children
                .map(\.plainText)
                .map(\.normalizedPreviewText)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            return (body.isEmpty ? callout.label : "\(callout.label) \(body)").normalizedPreviewText
        }

        return blockDirective.format().normalizedPreviewText
    }
}

private struct HeadingOutlineCollector: MarkupVisitor {
    typealias Result = [DocumentOutlineItem]

    private var slugger = HeadingAnchorSlugger()

    static func collect(from document: MarkdownDocument) -> [DocumentOutlineItem] {
        var collector = HeadingOutlineCollector()
        return collector.visit(document.ast)
    }

    mutating func visit(_ markup: Markup) -> [DocumentOutlineItem] {
        markup.accept(&self)
    }

    mutating func defaultVisit(_ markup: Markup) -> [DocumentOutlineItem] {
        markup.children.flatMap { visit($0) }
    }

    mutating func visitHeading(_ heading: Heading) -> [DocumentOutlineItem] {
        let title = heading.plainText.normalizedPreviewText
        guard !title.isEmpty else {
            return []
        }

        return [
            DocumentOutlineItem(
                title: title,
                level: heading.level,
                anchorID: slugger.slug(for: title)
            )
        ]
    }
}

struct HeadingAnchorSlugger {
    private var counts: [String: Int] = [:]

    mutating func slug(for title: String) -> String {
        let base = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stem = base.isEmpty ? "section" : base
        let count = (counts[stem] ?? 0) + 1
        counts[stem] = count
        if count == 1 {
            return stem
        }
        return "\(stem)-\(count)"
    }
}

private extension Markup {
    var plainText: String {
        switch self {
        case let text as Text:
            return text.string
        case is SoftBreak:
            return " "
        case is LineBreak:
            return "\n"
        case let inlineCode as InlineCode:
            return inlineCode.code
        case let symbolLink as SymbolLink:
            return symbolLink.destination ?? ""
        case let inlineAttributes as InlineAttributes:
            return inlineAttributes.children.map(\.plainText).joined()
        case let inlineHTML as InlineHTML:
            let source = inlineHTML.format()
            if MarkdownSemanticSupport.inlineHTMLTransition(from: source) == "kbd" {
                return ""
            }
            return MarkdownSemanticSupport.strippedHTMLText(from: source)
        case let html as HTMLBlock:
            return MarkdownSemanticSupport.strippedHTMLText(from: html.format())
        case let directive as BlockDirective:
            if let callout = MarkdownSemanticSupport.calloutDefinition(for: directive) {
                let body = directive.children
                    .map(\.plainText)
                    .map(\.normalizedPreviewText)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return body.isEmpty ? callout.label : "\(callout.label) \(body)"
            }
            return directive.format()
        default:
            return children.map(\.plainText).joined()
        }
    }
}

private extension String {
    var normalizedPreviewText: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var previewSnippet: String {
        let preview = normalizedPreviewText
        guard preview.count > 140 else {
            return preview
        }

        let index = preview.index(preview.startIndex, offsetBy: 140)
        return preview[..<index].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var strippingTaskListPrefix: String {
        let prefixes = ["[x] ", "[X] ", "[ ] "]
        for prefix in prefixes where hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}
