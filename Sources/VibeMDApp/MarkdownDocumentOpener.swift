import AppKit
import Foundation
import VibeMDCore

@MainActor
enum MarkdownDocumentOpener {
    static func open(urls: [URL]) {
        for url in urls {
            do {
                try open(url: url, anchorID: nil)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    static func open(url: URL, anchorID: String? = nil) throws {
        let normalizedURL = normalizedFileURL(for: url)
        guard supports(url: normalizedURL) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let requestedAnchorID = anchorID ?? url.fragment

        if let existingDocument = OpenDocumentRegistry.shared.document(for: normalizedURL) {
            focus(document: existingDocument)
            if let requestedAnchorID, !requestedAnchorID.isEmpty {
                existingDocument.navigateToAnchor(id: requestedAnchorID)
            }
            return
        }

        let cascadeSourceWindow = currentMarkdownWindow()
        let document = MarkdownReaderDocument()
        document.fileURL = normalizedURL
        document.initialCascadeSourceWindow = cascadeSourceWindow
        if let requestedAnchorID, !requestedAnchorID.isEmpty {
            document.navigateToAnchor(id: requestedAnchorID)
        }
        let data = try Data(contentsOf: normalizedURL)
        try document.read(from: data, ofType: "dev.vibemd.markdown")
        NSDocumentController.shared.addDocument(document)
        OpenDocumentRegistry.shared.retain(document)
        document.makeWindowControllers()
        focus(document: document)
    }

    static func supports(url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        return AssetResolver.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func release(document: NSDocument) {
        OpenDocumentRegistry.shared.release(document)
    }

    static var retainedDocumentCountForTesting: Int {
        OpenDocumentRegistry.shared.count
    }

    static func currentMarkdownWindowForTesting() -> NSWindow? {
        currentMarkdownWindow()
    }

    static func normalizedFileURL(for url: URL) -> URL {
        guard url.isFileURL else {
            return url
        }

        let standardizedURL = url.standardizedFileURL
        return URL(fileURLWithPath: standardizedURL.path)
    }

    private static func focus(document: MarkdownReaderDocument) {
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
        }

        let windowControllers = document.windowControllers.isEmpty ? [] : document.windowControllers
        for windowController in windowControllers {
            windowController.showWindow(nil)
        }

        if let window = preferredWindow(for: document) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private static func preferredWindow(for document: MarkdownReaderDocument) -> NSWindow? {
        document.windowControllers
            .compactMap(\.window)
            .sorted { lhs, rhs in
                if lhs.isVisible != rhs.isVisible {
                    return lhs.isVisible && !rhs.isVisible
                }
                return lhs.isKeyWindow && !rhs.isKeyWindow
            }
            .first
    }

    private static func currentMarkdownWindow() -> NSWindow? {
        let candidateWindows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        if let foregroundWindow = candidateWindows.first(where: isMarkdownWindow(_:)) {
            return foregroundWindow
        }

        return NSDocumentController.shared.documents
            .compactMap { $0 as? MarkdownReaderDocument }
            .flatMap(\.windowControllers)
            .compactMap(\.window)
            .last(where: { $0.isVisible })
    }

    private static func isMarkdownWindow(_ window: NSWindow) -> Bool {
        window.windowController?.document is MarkdownReaderDocument
    }
}

@MainActor
final class OpenDocumentRegistry {
    static let shared = OpenDocumentRegistry()

    private var documents: [ObjectIdentifier: NSDocument] = [:]
    private var documentIdentities: [String: Set<ObjectIdentifier>] = [:]

    var count: Int {
        documents.count
    }

    func retain(_ document: NSDocument) {
        let identifier = ObjectIdentifier(document)
        documents[identifier] = document
        if let identity = identity(for: document) {
            documentIdentities[identity, default: []].insert(identifier)
        }
    }

    func release(_ document: NSDocument) {
        let identifier = ObjectIdentifier(document)
        documents.removeValue(forKey: identifier)
        remove(identifier: identifier)
    }

    func document(for url: URL) -> MarkdownReaderDocument? {
        let identity = Self.identity(for: url)
        guard let identifiers = documentIdentities[identity], !identifiers.isEmpty else {
            return nil
        }

        let candidates = identifiers.compactMap { documents[$0] as? MarkdownReaderDocument }
        if candidates.isEmpty {
            documentIdentities.removeValue(forKey: identity)
            return nil
        }

        return preferredDocument(from: candidates)
    }

    func reindex(_ document: NSDocument) {
        let identifier = ObjectIdentifier(document)
        documents[identifier] = document
        remove(identifier: identifier)
        if let identity = identity(for: document) {
            documentIdentities[identity, default: []].insert(identifier)
        }
    }

    private func identity(for document: NSDocument) -> String? {
        guard let fileURL = document.fileURL else {
            return nil
        }

        return Self.identity(for: fileURL)
    }

    private static func identity(for url: URL) -> String {
        MarkdownDocumentOpener.normalizedFileURL(for: url).path
    }

    private func remove(identifier: ObjectIdentifier) {
        var updatedIdentities: [String: Set<ObjectIdentifier>] = [:]
        for (identity, identifiers) in documentIdentities {
            let filtered = identifiers.filter { $0 != identifier }
            if !filtered.isEmpty {
                updatedIdentities[identity] = filtered
            }
        }
        documentIdentities = updatedIdentities
    }

    private func preferredDocument(from documents: [MarkdownReaderDocument]) -> MarkdownReaderDocument? {
        documents.max { lhs, rhs in
            documentScore(lhs) < documentScore(rhs)
        }
    }

    private func documentScore(_ document: MarkdownReaderDocument) -> Int {
        guard let window = document.windowControllers.compactMap(\.window).first else {
            return 0
        }

        var score = 0
        if window.isVisible {
            score += 1
        }
        if window.isMainWindow {
            score += 2
        }
        if window.isKeyWindow {
            score += 4
        }
        return score
    }
}
