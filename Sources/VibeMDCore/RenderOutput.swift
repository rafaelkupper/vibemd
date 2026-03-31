import Foundation

public struct WebKitRenderOutput: Equatable, Sendable {
    public let html: String
    public let baseURL: URL?
    public let statistics: DocumentStatistics
    public let sidebarEntries: [DocumentSidebarEntry]
    public let outlineItems: [DocumentOutlineItem]

    public init(
        html: String,
        baseURL: URL?,
        statistics: DocumentStatistics = .zero,
        sidebarEntries: [DocumentSidebarEntry] = [],
        outlineItems: [DocumentOutlineItem] = []
    ) {
        self.html = html
        self.baseURL = baseURL
        self.statistics = statistics
        self.sidebarEntries = sidebarEntries
        self.outlineItems = outlineItems
    }
}
