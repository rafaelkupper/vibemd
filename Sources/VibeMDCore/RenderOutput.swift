import Foundation

public struct WebKitRenderOutput: Equatable {
    public let html: String
    public let baseURL: URL?

    public init(html: String, baseURL: URL?) {
        self.html = html
        self.baseURL = baseURL
    }
}
