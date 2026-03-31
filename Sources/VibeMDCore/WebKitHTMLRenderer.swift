import CoreGraphics
import Foundation
import Markdown

public final class WebKitHTMLRenderer {
    private let assetResolver: AssetResolver
    private let codeSyntaxHighlighter = CodeSyntaxHighlighter()

    public init(assetResolver: AssetResolver = AssetResolver()) {
        self.assetResolver = assetResolver
    }

    public func render(document: MarkdownDocument) -> WebKitRenderOutput {
        let statistics = RenderedTextDocumentStatistics.statistics(from: document)
        let sidebarEntries = DocumentSidebarDataBuilder.sidebarEntries(
            from: document,
            assetResolver: assetResolver
        )
        let outlineItems = DocumentSidebarDataBuilder.outlineItems(from: document)
        var visitor = WebKitHTMLRenderVisitor(
            baseURL: document.baseURL,
            assetResolver: assetResolver,
            codeSyntaxHighlighter: codeSyntaxHighlighter
        )
        let body = visitor.visit(document.ast)
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
          \(ReaderTheme.styleSheet)
          </style>
        </head>
        <body>
          <div id="write">
          \(body)
          </div>
        </body>
        </html>
        """

        return WebKitRenderOutput(
            html: html,
            baseURL: document.baseURL?.deletingLastPathComponent(),
            statistics: statistics,
            sidebarEntries: sidebarEntries,
            outlineItems: outlineItems
        )
    }
}

private struct WebKitHTMLRenderVisitor: MarkupVisitor {
    typealias Result = String

    let baseURL: URL?
    let assetResolver: AssetResolver
    let codeSyntaxHighlighter: CodeSyntaxHighlighter
    private var headingSlugger = HeadingAnchorSlugger()
    private var inTableHead = false
    private var currentTableColumn = 0
    private var currentTableColumnAlignments: [Table.ColumnAlignment?] = []

    init(
        baseURL: URL?,
        assetResolver: AssetResolver,
        codeSyntaxHighlighter: CodeSyntaxHighlighter
    ) {
        self.baseURL = baseURL
        self.assetResolver = assetResolver
        self.codeSyntaxHighlighter = codeSyntaxHighlighter
    }

    private var readAccessDirectoryURL: URL? {
        guard let baseURL else {
            return nil
        }

        guard baseURL.isFileURL else {
            return baseURL
        }

        return baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
    }

    mutating func visit(_ markup: Markup) -> String {
        markup.accept(&self)
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        if markup is BlockMarkup {
            return "<p class=\"fallback-block\">\(markup.format().escapedHTML)</p>"
        }

        return descend(markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        descend(document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(descend(paragraph))</p>"
    }

    mutating func visitText(_ text: Text) -> String {
        text.string.escapedHTML
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br />"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(descend(strong))</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(descend(emphasis))</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(descend(strikethrough))</del>"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let title = heading.plainText.normalizedHeadingText
        let idAttribute: String
        if title.isEmpty {
            idAttribute = ""
        } else {
            idAttribute = " id=\"\(headingSlugger.slug(for: title).escapedHTMLAttribute)\""
        }
        return "<h\(heading.level)\(idAttribute)>\(descend(heading))</h\(heading.level)>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(inlineCode.code.escapedHTML)</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let normalizedLanguage = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let languageClass = normalizedLanguage.isEmpty ? "" : " language-\(normalizedLanguage.escapedHTMLAttribute)"

        let highlighted = codeSyntaxHighlighter.highlightedHTML(
            code: codeBlock.code.trimmingCharacters(in: .newlines),
            language: codeBlock.language
        )
        let languageAttribute = normalizedLanguage.isEmpty ? "" : " lang=\"\(normalizedLanguage.escapedHTMLAttribute)\""
        return "<pre class=\"md-fences\"\(languageAttribute)><code class=\"cm-s-inner\(languageClass)\">\(highlighted)</code></pre>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let href = resolvedHTMLURLString(
            for: assetResolver.resolve(destination: link.destination ?? "", relativeTo: baseURL)
        ) ?? (link.destination ?? "")
        return "<a href=\"\(href.escapedHTMLAttribute)\">\(descend(link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let altText = image.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let source = image.source,
            let url = assetResolver.imageURL(for: source, relativeTo: baseURL)
        else {
            return "<p class=\"fallback-block\">[Missing image]</p>"
        }

        let sourceURL = webViewAssetURLString(for: url)
        return "<img src=\"\(sourceURL.escapedHTMLAttribute)\" alt=\"\(altText.escapedHTMLAttribute)\" />"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\(descend(blockQuote))</blockquote>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let containsTasks = unorderedList.children.contains { child in
            guard let listItem = child as? ListItem else {
                return false
            }
            return taskListState(for: listItem) != nil
        }

        let classAttribute = containsTasks ? " class=\"task-list\"" : ""
        return "<ul\(classAttribute)>\(descend(unorderedList))</ul>"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let startAttribute = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        return "<ol\(startAttribute)>\(descend(orderedList))</ol>"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let content = flattenLeadingParagraphIfPresent(descend(listItem).strippingTaskListPrefix)

        if let taskState = taskListState(for: listItem) {
            let checkedAttribute = taskState ? " checked" : ""
            return "<li class=\"md-task-list-item\"><input type=\"checkbox\" disabled\(checkedAttribute) />\(content)</li>"
        }

        return "<li>\(content)</li>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr />"
    }

    mutating func visitTable(_ table: Table) -> String {
        guard !table.isEmpty, table.maxColumnCount > 0 else {
            return "<p class=\"fallback-block\">\(table.format().escapedHTML)</p>"
        }

        let rows = tableTextRows(for: table)
        let columnWidths = tableColumnWidthPercentages(for: rows, columnCount: table.maxColumnCount)
        let columns = columnWidths.map { width in
            "<col style=\"width: \(width)%\">"
        }.joined()

        let previousAlignments = currentTableColumnAlignments
        let previousColumn = currentTableColumn
        let previousInHead = inTableHead

        currentTableColumnAlignments = normalizedTableColumnAlignments(for: table)
        currentTableColumn = 0
        inTableHead = false
        let content = descend(table)

        currentTableColumnAlignments = previousAlignments
        currentTableColumn = previousColumn
        inTableHead = previousInHead

        return """
        <table>
          <colgroup>\(columns)</colgroup>
          \(content)
        </table>
        """
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        let previousInHead = inTableHead
        let previousColumn = currentTableColumn
        inTableHead = true
        currentTableColumn = 0
        let content = descend(tableHead)
        inTableHead = previousInHead
        currentTableColumn = previousColumn
        return "<thead><tr>\(content)</tr></thead>"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        guard !tableBody.isEmpty else {
            return ""
        }

        return "<tbody>\(descend(tableBody))</tbody>"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        let previousColumn = currentTableColumn
        currentTableColumn = 0
        let content = descend(tableRow)
        currentTableColumn = previousColumn
        return "<tr>\(content)</tr>"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else {
            currentTableColumn += 1
            return ""
        }

        let element = inTableHead ? "th" : "td"
        let colspan = max(Int(tableCell.colspan), 1)
        let rowspan = max(Int(tableCell.rowspan), 1)
        let columnIndex = currentTableColumn
        currentTableColumn += colspan

        var attributes = ""
        if columnIndex < currentTableColumnAlignments.count,
           let alignment = currentTableColumnAlignments[columnIndex] {
            attributes += " align=\"\(htmlAlignmentValue(for: alignment))\""
        }
        if rowspan > 1 {
            attributes += " rowspan=\"\(rowspan)\""
        }
        if colspan > 1 {
            attributes += " colspan=\"\(colspan)\""
        }

        return "<\(element)\(attributes)>\(descend(tableCell))</\(element)>"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        let stripped = strippedHTMLText(from: html.format())
        guard !stripped.isEmpty else {
            return ""
        }
        return "<p class=\"fallback-block\">\(stripped.escapedHTML)</p>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        let source = inlineHTML.format()
        if let transition = inlineHTMLTransition(from: source), transition == "kbd" {
            if source.contains("/") {
                return "</kbd>"
            }
            return "<kbd>"
        }

        return strippedHTMLText(from: source).escapedHTML
    }

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> String {
        "<p class=\"fallback-block\">\(blockDirective.format().escapedHTML)</p>"
    }

    private mutating func descend(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    private func tableColumnWidthPercentages(for rows: [[String]], columnCount: Int) -> [CGFloat] {
        guard columnCount > 0 else {
            return []
        }

        switch columnCount {
        case 3:
            return [20, 30, 50]
        case 4:
            return [15, 22, 51, 12]
        default:
            break
        }

        var weights = Array(repeating: CGFloat(1), count: columnCount)
        for row in rows {
            for columnIndex in 0..<columnCount {
                let text = columnIndex < row.count ? row[columnIndex] : ""
                let characterCount = text.count
                let longestWordCount = text
                    .split(whereSeparator: \.isWhitespace)
                    .map(\.count)
                    .max() ?? 0
                let weight = CGFloat(min(max(characterCount + (longestWordCount / 2), 8), 36))
                weights[columnIndex] = max(weights[columnIndex], weight)
            }
        }

        if let narrowColumnIndex = weights.indices.last {
            weights[narrowColumnIndex] = min(weights[narrowColumnIndex], 10)
        }

        if let widestColumnIndex = weights.indices.max(by: { weights[$0] < weights[$1] }) {
            weights[widestColumnIndex] *= 1.15
        }

        let minimums = Array(repeating: CGFloat(12), count: columnCount)
        let totalMinimum = minimums.reduce(0, +)
        guard totalMinimum < 100 else {
            return Array(repeating: 100 / CGFloat(columnCount), count: columnCount)
        }

        let normalizedWeights = zip(weights, minimums).map { max($0 - $1, 1) }
        let normalizedWeightTotal = normalizedWeights.reduce(0, +)
        let distributableWidth = 100 - totalMinimum

        return zip(minimums, normalizedWeights).map { minimum, weight in
            minimum + (distributableWidth * weight / normalizedWeightTotal)
        }
    }

    private func tableTextRows(for table: Table) -> [[String]] {
        var rows = [tableTextRow(for: table.head, columnCount: table.maxColumnCount)]
        rows.append(contentsOf: table.body.rows.map { tableTextRow(for: $0, columnCount: table.maxColumnCount) })
        return rows
    }

    private func tableTextRow(for row: some Markup, columnCount: Int) -> [String] {
        let cells = row.children.compactMap { $0 as? Table.Cell }
        var texts: [String] = []

        for cell in cells {
            if cell.colspan == 0 || cell.rowspan == 0 {
                texts.append("")
                continue
            }

            let colspan = max(Int(cell.colspan), 1)
            texts.append(cell.plainText.normalizedHeadingText)
            if colspan > 1 {
                texts.append(contentsOf: repeatElement("", count: colspan - 1))
            }
        }

        if texts.count < columnCount {
            texts.append(contentsOf: repeatElement("", count: columnCount - texts.count))
        } else if texts.count > columnCount {
            texts = Array(texts.prefix(columnCount))
        }

        return texts
    }

    private func normalizedTableColumnAlignments(for table: Table) -> [Table.ColumnAlignment?] {
        var alignments = table.columnAlignments
        if alignments.count < table.maxColumnCount {
            alignments.append(contentsOf: repeatElement(nil, count: table.maxColumnCount - alignments.count))
        } else if alignments.count > table.maxColumnCount {
            alignments = Array(alignments.prefix(table.maxColumnCount))
        }
        return alignments
    }

    private func htmlAlignmentValue(for alignment: Table.ColumnAlignment) -> String {
        switch alignment {
        case .left:
            return "left"
        case .center:
            return "center"
        case .right:
            return "right"
        }
    }

    private func taskListState(for listItem: ListItem) -> Bool? {
        switch listItem.checkbox {
        case .checked?:
            true
        case .unchecked?:
            false
        case nil:
            nil
        }
    }

    private func inlineHTMLTransition(from source: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: #"^<\s*/?\s*([A-Za-z0-9]+)[^>]*>$"#),
            let match = regex.firstMatch(in: source, options: [], range: NSRange(location: 0, length: source.utf16.count)),
            let nameRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return source[nameRange].lowercased()
    }

    private func strippedHTMLText(from source: String) -> String {
        source
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func flattenLeadingParagraphIfPresent(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<p>"), let closingRange = trimmed.range(of: "</p>") else {
            return html
        }

        let paragraphStart = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let firstParagraph = String(trimmed[paragraphStart..<closingRange.lowerBound])
        let remainder = trimmed[closingRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? firstParagraph : firstParagraph + remainder
    }

    private func resolvedHTMLURLString(for url: URL?) -> String? {
        guard let url else {
            return nil
        }

        guard url.isFileURL else {
            return url.absoluteString
        }

        guard
            let readAccessDirectoryURL,
            readAccessDirectoryURL.isFileURL,
            let relativePath = relativePath(from: readAccessDirectoryURL, to: url)
        else {
            return url.absoluteString
        }

        return relativePath
    }

    private func relativePath(from directoryURL: URL, to fileURL: URL) -> String? {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL
        let standardizedFileURL = standardizedFileURLPreservingFragment(fileURL)

        let directoryPath = standardizedDirectoryURL.path
        let filePath = standardizedFileURL.path
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"

        guard filePath.hasPrefix(prefix) else {
            return nil
        }

        let relativePath = String(filePath.dropFirst(prefix.count))
        let encodedPath = relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")

        if let fragment = standardizedFileURL.fragment {
            let encodedFragment = fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment
            return encodedPath + "#" + encodedFragment
        }

        return encodedPath
    }

    private func standardizedFileURLPreservingFragment(_ url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        guard let fragment = url.fragment else {
            return standardizedURL
        }

        var components = URLComponents(url: standardizedURL, resolvingAgainstBaseURL: false)
        components?.fragment = fragment
        return components?.url ?? standardizedURL
    }

    private func webViewAssetURLString(for fileURL: URL) -> String {
        var components = URLComponents()
        components.scheme = "vibemd-local"
        components.host = "asset"
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.standardizedFileURL.path),
        ]
        return components.url?.absoluteString ?? fileURL.absoluteString
    }
}

private extension Markup {
    var plainText: String {
        children.map { child in
            if let text = child as? Text {
                return text.string
            }
            return child.plainText
        }.joined()
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

    var escapedHTMLAttribute: String {
        escapedHTML.replacingOccurrences(of: "'", with: "&#39;")
    }

    var strippingTaskListPrefix: String {
        let prefixes = ["[x] ", "[X] ", "[ ] "]
        for prefix in prefixes where hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }

    var normalizedHeadingText: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
