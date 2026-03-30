import AppKit
import Foundation
import VibeMDCore

@MainActor
enum MarkdownDocumentOpener {
    static func open(urls: [URL]) {
        for url in urls {
            do {
                try open(url: url)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    static func open(url: URL) throws {
        let normalizedURL = normalizedFileURL(for: url)
        guard supports(url: normalizedURL) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        if let existingDocument = OpenDocumentRegistry.shared.document(for: normalizedURL) {
            focus(document: existingDocument)
            return
        }

        let cascadeSourceWindow = currentMarkdownWindow()
        let document = MarkdownReaderDocument()
        document.fileURL = normalizedURL
        document.initialCascadeSourceWindow = cascadeSourceWindow
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
private final class OpenDocumentRegistry {
    static let shared = OpenDocumentRegistry()

    private var documents: [ObjectIdentifier: NSDocument] = [:]
    private var documentIdentities: [String: ObjectIdentifier] = [:]

    var count: Int {
        documents.count
    }

    func retain(_ document: NSDocument) {
        let identifier = ObjectIdentifier(document)
        documents[identifier] = document
        if let identity = identity(for: document) {
            documentIdentities[identity] = identifier
        }
    }

    func release(_ document: NSDocument) {
        let identifier = ObjectIdentifier(document)
        documents.removeValue(forKey: identifier)
        documentIdentities = documentIdentities.filter { $0.value != identifier }
    }

    func document(for url: URL) -> MarkdownReaderDocument? {
        let identity = Self.identity(for: url)
        guard let objectIdentifier = documentIdentities[identity] else {
            return nil
        }

        guard let document = documents[objectIdentifier] as? MarkdownReaderDocument else {
            documentIdentities.removeValue(forKey: identity)
            return nil
        }

        return document
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
}
