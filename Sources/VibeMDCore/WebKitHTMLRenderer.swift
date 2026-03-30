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
            baseURL: document.baseURL?.deletingLastPathComponent()
        )
    }
}

private struct WebKitHTMLRenderVisitor: MarkupVisitor {
    typealias Result = String

    let baseURL: URL?
    let assetResolver: AssetResolver
    let codeSyntaxHighlighter: CodeSyntaxHighlighter

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
        "<h\(heading.level)>\(descend(heading))</h\(heading.level)>"
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
        tableHTML(from: table.format())
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

    private func tableHTML(from markdown: String) -> String {
        let rows = parseTableRows(from: markdown)
        guard !rows.isEmpty else {
            return "<p class=\"fallback-block\">\(markdown.escapedHTML)</p>"
        }

        let header = rows.first ?? []
        let bodyRows = Array(rows.dropFirst())
        let columnWidths = tableColumnWidthPercentages(for: rows, columnCount: header.count)
        let columns = columnWidths.map { width in
            "<col style=\"width: \(width)%\">"
        }.joined()
        let headerHTML = header.map { "<th>\($0.escapedHTML)</th>" }.joined()
        let bodyHTML = bodyRows.map { row in
            "<tr>\(row.map { "<td>\($0.escapedHTML)</td>" }.joined())</tr>"
        }.joined()

        return """
        <table>
          <colgroup>\(columns)</colgroup>
          <thead><tr>\(headerHTML)</tr></thead>
          <tbody>\(bodyHTML)</tbody>
        </table>
        """
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

    private func parseTableRows(from markdown: String) -> [[String]] {
        let lines = markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("|") }

        var rows: [[String]] = []
        for (index, line) in lines.enumerated() {
            if index == 1, isAlignmentRow(line) {
                continue
            }

            let rawCells = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            let cells = rawCells.filter { !$0.isEmpty }
            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        return rows
    }

    private func isAlignmentRow(_ line: String) -> Bool {
        let candidate = line.replacingOccurrences(of: "|", with: "")
        let charset = CharacterSet(charactersIn: ":- ")
        return candidate.unicodeScalars.allSatisfy { charset.contains($0) }
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
}
