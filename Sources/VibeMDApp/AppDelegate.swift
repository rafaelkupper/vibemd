import AppKit
import UniformTypeIdentifiers
import VibeMDCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias URLOpenHandler = @MainActor ([URL]) -> Void
    typealias URLSupportHandler = @MainActor (URL) -> Bool

    private let openURLs: URLOpenHandler
    private let supportsURL: URLSupportHandler

    init(
        openURLs: @escaping URLOpenHandler = MarkdownDocumentOpener.open(urls:),
        supportsURL: @escaping URLSupportHandler = MarkdownDocumentOpener.supports(url:)
    ) {
        self.openURLs = openURLs
        self.supportsURL = supportsURL
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc
    func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = AssetResolver.markdownExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }

        guard panel.runModal() == .OK else {
            return
        }

        openURLs(panel.urls)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openURLs(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard supportsURL(url) else {
            return false
        }

        openURLs([url])
        return true
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }.filter(supportsURL)
        openURLs(urls)
        application.reply(toOpenOrPrint: .success)
    }
}
