import CryptoKit
import Foundation
import Markdown

public struct MarkdownDocument {
    public let source: String
    public let baseURL: URL?
    public let ast: Document
    public let fingerprint: String

    public init(source: String, baseURL: URL?, ast: Document, fingerprint: String) {
        self.source = source
        self.baseURL = baseURL
        self.ast = ast
        self.fingerprint = fingerprint
    }
}

public enum FileFingerprint {
    public static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(for string: String) -> String {
        sha256Hex(for: Data(string.utf8))
    }
}

