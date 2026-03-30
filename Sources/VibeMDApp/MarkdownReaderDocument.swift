import AppKit
import Foundation
import VibeMDCore

final class MarkdownReaderDocument: NSDocument {
    typealias RenderScheduler = (
        _ source: String,
        _ baseURL: URL?,
        _ completion: @escaping (WebKitRenderOutput) -> Void
    ) -> DispatchWorkItem
    typealias LinkTargetHandler = @MainActor (LinkTarget) -> Void
    typealias ReaderControllerFactory = () -> WebKitReaderViewController

    private let assetResolver: AssetResolver
    private let scrollStateStore: ScrollStateStore
    private let renderScheduler: RenderScheduler
    private let linkTargetHandler: LinkTargetHandler
    private let readerControllerFactory: ReaderControllerFactory

    private var sourceText = ""
    private var fileFingerprint = ""
    private weak var readerController: WebKitReaderViewController?
    private var renderWorkItem: DispatchWorkItem?
    private var renderToken = UUID()
    var initialCascadeSourceWindow: NSWindow?

    init(
        assetResolver: AssetResolver = AssetResolver(),
        scrollStateStore: ScrollStateStore = ScrollStateStore(),
        renderScheduler: @escaping RenderScheduler = MarkdownRenderWorker.schedule,
        linkTargetHandler: @escaping LinkTargetHandler = MarkdownReaderDocument.defaultHandle,
        readerControllerFactory: @escaping ReaderControllerFactory = { WebKitReaderViewController() }
    ) {
        self.assetResolver = assetResolver
        self.scrollStateStore = scrollStateStore
        self.renderScheduler = renderScheduler
        self.linkTargetHandler = linkTargetHandler
        self.readerControllerFactory = readerControllerFactory
        super.init()
    }

    override class var autosavesInPlace: Bool {
        false
    }

    override class var readableTypes: [String] {
        ["dev.vibemd.markdown", "net.daringfireball.markdown"]
    }

    override class var writableTypes: [String] {
        []
    }

    override func makeWindowControllers() {
        let readerController = makeReaderController()
        let windowController = DocumentWindowController(
            contentViewController: readerController,
            cascadeFrom: initialCascadeSourceWindow
        )
        addWindowController(windowController)
        self.readerController = readerController
        initialCascadeSourceWindow = nil

        if let fileURL {
            windowController.window?.title = fileURL.lastPathComponent
            readerController.displayLoading(for: fileURL.lastPathComponent)
        } else {
            readerController.displayLoading(for: "Markdown")
        }

        scheduleRenderIfPossible()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decodedSource: String
        if let decoded = String(data: data, encoding: .utf8) {
            decodedSource = decoded
        } else {
            decodedSource = String(decoding: data, as: UTF8.self)
        }
        let fingerprint = FileFingerprint.sha256Hex(for: data)

        MainActor.assumeIsolated {
            sourceText = decodedSource
            fileFingerprint = fingerprint
            scheduleRenderIfPossible()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    override func close() {
        persistCurrentScrollFraction()
        renderWorkItem?.cancel()
        MarkdownDocumentOpener.release(document: self)
        super.close()
    }

    private func scheduleRenderIfPossible() {
        scheduleRenderIfPossible(initialScrollFractionOverride: nil)
    }

    private func scheduleRenderIfPossible(initialScrollFractionOverride: Double?) {
        guard !sourceText.isEmpty, let readerController else {
            return
        }

        let sourceText = sourceText
        let fileURL = fileURL
        let restoreFraction = initialScrollFractionOverride ?? fileURL.flatMap {
            scrollStateStore.load(for: $0, fingerprint: fileFingerprint)?.fraction
        }
        let token = UUID()
        renderToken = token

        renderWorkItem?.cancel()
        readerController.displayLoading(for: fileURL?.lastPathComponent ?? "Markdown")
        renderWorkItem = renderScheduler(sourceText, fileURL) { [weak self] output in
            guard let self, self.renderToken == token else {
                return
            }

            self.readerController?.apply(renderOutput: output, initialScrollFraction: restoreFraction)
        }
    }

    private func openResolvedLink(_ url: URL) {
        linkTargetHandler(assetResolver.classify(url))
    }

    private func persistScrollFraction(_ fraction: Double) {
        guard let fileURL, !fileFingerprint.isEmpty else {
            return
        }

        scrollStateStore.save(fraction: fraction, for: fileURL, fingerprint: fileFingerprint)
    }

    private func persistCurrentScrollFraction() {
        guard let fraction = readerController?.currentScrollFraction else {
            return
        }

        persistScrollFraction(fraction)
    }

    private func makeReaderController() -> WebKitReaderViewController {
        let readerController = readerControllerFactory()
        readerController.onOpenLink = { [weak self] url in
            self?.openResolvedLink(url)
        }
        readerController.onScrollPositionChange = { [weak self] fraction in
            self?.persistScrollFraction(fraction)
        }
        return readerController
    }

    private static func defaultHandle(_ linkTarget: LinkTarget) {
        switch linkTarget {
        case .external(let externalURL):
            NSWorkspace.shared.open(externalURL)
        case .markdownFile(let markdownURL):
            MarkdownDocumentOpener.open(urls: [markdownURL])
        case .otherFile(let fileURL):
            NSWorkspace.shared.open(fileURL)
        case .unresolved:
            break
        }
    }
}

private enum MarkdownRenderWorker {
    static func schedule(
        source: String,
        baseURL: URL?,
        completion: @escaping (WebKitRenderOutput) -> Void
    ) -> DispatchWorkItem {
        let completionBox = RenderCompletionBox(completion: completion)
        let workItem = DispatchWorkItem {
            let parser = MarkdownParser()
            let parsed = parser.parse(source: source, baseURL: baseURL)
            let output = WebKitHTMLRenderer().render(document: parsed)

            DispatchQueue.main.async {
                completionBox.completion(output)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        return workItem
    }
}

private final class RenderCompletionBox: @unchecked Sendable {
    let completion: (WebKitRenderOutput) -> Void

    init(completion: @escaping (WebKitRenderOutput) -> Void) {
        self.completion = completion
    }
}
