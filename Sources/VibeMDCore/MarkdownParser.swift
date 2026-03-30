import Foundation
import Markdown

public final class MarkdownParser {
    public init() {}

    public func parse(source: String, baseURL: URL?) -> MarkdownDocument {
        let ast = Document(parsing: source, options: [.parseBlockDirectives])
        return MarkdownDocument(
            source: source,
            baseURL: baseURL,
            ast: ast,
            fingerprint: FileFingerprint.sha256Hex(for: source)
        )
    }
}

