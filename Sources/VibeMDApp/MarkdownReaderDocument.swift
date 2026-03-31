import AppKit
import Foundation
import VibeMDCore

final class MarkdownReaderDocument: NSDocument {
    typealias RenderScheduler = (
        _ source: String,
        _ baseURL: URL?,
        _ completion: @escaping (WebKitRenderOutput) -> Void
    ) -> DispatchWorkItem
    typealias MarkdownLinkOpener = @MainActor (_ url: URL, _ anchorID: String?) -> Void
    typealias LinkTargetHandler = @MainActor (LinkTarget) -> Void
    typealias ReaderControllerFactory = () -> WebKitReaderViewController
    typealias SourceLoader = @Sendable (_ fileURL: URL) throws -> LoadedMarkdownSource

    private let assetResolver: AssetResolver
    private let scrollStateStore: ScrollStateStore
    private let renderScheduler: RenderScheduler
    private let markdownLinkOpener: MarkdownLinkOpener
    private let linkTargetHandler: LinkTargetHandler
    private let readerControllerFactory: ReaderControllerFactory
    private let statisticPreferenceStore: DocumentStatisticPreferenceStore
    private let sourceLoader: SourceLoader

    private var sourceText = ""
    private var fileFingerprint = ""
    private weak var readerController: WebKitReaderViewController?
    private weak var documentWindowController: DocumentWindowController?
    private var renderWorkItem: DispatchWorkItem?
    private var renderToken = UUID()
    private var sourceLoadToken = UUID()
    private var currentStatistics: DocumentStatistics?
    private var currentSidebarEntries: [DocumentSidebarEntry] = []
    private var currentOutlineItems: [DocumentOutlineItem] = []
    private var currentActiveHeadingID: String?
    private var pendingNavigationAnchorID: String?
    private var consumePendingAnchorOnNextNavigationFinish = false
    var initialCascadeSourceWindow: NSWindow?

    override init() {
        self.assetResolver = AssetResolver()
        self.scrollStateStore = ScrollStateStore()
        self.renderScheduler = MarkdownRenderWorker.schedule
        self.markdownLinkOpener = MarkdownReaderDocument.defaultOpenMarkdownLink
        self.linkTargetHandler = MarkdownReaderDocument.defaultHandle
        self.readerControllerFactory = { WebKitReaderViewController() }
        self.statisticPreferenceStore = .shared
        self.sourceLoader = MarkdownReaderDocument.loadSource
        super.init()
    }

    init(
        assetResolver: AssetResolver = AssetResolver(),
        scrollStateStore: ScrollStateStore = ScrollStateStore(),
        renderScheduler: @escaping RenderScheduler = MarkdownRenderWorker.schedule,
        markdownLinkOpener: @escaping MarkdownLinkOpener = MarkdownReaderDocument.defaultOpenMarkdownLink,
        linkTargetHandler: @escaping LinkTargetHandler = MarkdownReaderDocument.defaultHandle,
        readerControllerFactory: @escaping ReaderControllerFactory = { WebKitReaderViewController() },
        statisticPreferenceStore: DocumentStatisticPreferenceStore = .shared,
        sourceLoader: @escaping SourceLoader = MarkdownReaderDocument.loadSource
    ) {
        self.assetResolver = assetResolver
        self.scrollStateStore = scrollStateStore
        self.renderScheduler = renderScheduler
        self.markdownLinkOpener = markdownLinkOpener
        self.linkTargetHandler = linkTargetHandler
        self.readerControllerFactory = readerControllerFactory
        self.statisticPreferenceStore = statisticPreferenceStore
        self.sourceLoader = sourceLoader
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
            cascadeFrom: initialCascadeSourceWindow,
            statisticPreferenceStore: statisticPreferenceStore
        )
        addWindowController(windowController)
        self.readerController = readerController
        self.documentWindowController = windowController
        initialCascadeSourceWindow = nil
        windowController.apply(documentStatistics: currentStatistics)
        windowController.apply(sidebarEntries: currentSidebarEntries, outlineItems: currentOutlineItems)
        windowController.setActiveOutlineAnchorID(currentActiveHeadingID)
        windowController.onSelectSidebarDocument = { [weak self] url in
            self?.navigateInCurrentWindow(to: url)
        }
        windowController.onSelectOutlineItem = { [weak readerController] anchorID in
            readerController?.scrollToHeading(id: anchorID)
        }

        if let fileURL {
            windowController.setDisplayedTitle(fileURL.lastPathComponent)
            readerController.displayLoading(for: fileURL.lastPathComponent)
        } else {
            windowController.setDisplayedTitle("Markdown")
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
        let restoreFraction: Double?
        if pendingNavigationAnchorID == nil {
            restoreFraction = initialScrollFractionOverride ?? fileURL.flatMap {
                scrollStateStore.load(for: $0, fingerprint: fileFingerprint)?.fraction
            }
        } else {
            restoreFraction = nil
        }
        let token = UUID()
        renderToken = token
        currentStatistics = nil
        currentActiveHeadingID = nil

        renderWorkItem?.cancel()
        readerController.displayLoading(for: fileURL?.lastPathComponent ?? "Markdown")
        documentWindowController?.apply(documentStatistics: nil)
        documentWindowController?.setActiveOutlineAnchorID(nil)
        renderWorkItem = renderScheduler(sourceText, fileURL) { [weak self] output in
            guard let self, self.renderToken == token else {
                return
            }

            self.currentStatistics = output.statistics
            self.currentSidebarEntries = output.sidebarEntries
            self.currentOutlineItems = output.outlineItems
            self.documentWindowController?.apply(documentStatistics: output.statistics)
            self.documentWindowController?.apply(sidebarEntries: output.sidebarEntries, outlineItems: output.outlineItems)
            self.consumePendingAnchorOnNextNavigationFinish = self.pendingNavigationAnchorID != nil
            self.readerController?.apply(renderOutput: output, initialScrollFraction: restoreFraction)
        }
    }

    private func openResolvedLink(_ url: URL) {
        if let sameDocumentAnchorID = sameDocumentAnchorID(for: url) {
            readerController?.scrollToHeading(id: sameDocumentAnchorID)
            return
        }

        let target = assetResolver.classify(url)
        switch target {
        case .markdownFile(let markdownURL):
            markdownLinkOpener(
                MarkdownDocumentOpener.normalizedFileURL(for: markdownURL),
                markdownURL.fragment
            )
        default:
            linkTargetHandler(target)
        }
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
        readerController.onActiveHeadingChange = { [weak self] anchorID in
            self?.currentActiveHeadingID = anchorID
            self?.documentWindowController?.setActiveOutlineAnchorID(anchorID)
        }
        readerController.onNavigationFinished = { [weak self, weak readerController] in
            self?.consumePendingNavigationAnchorIfNeeded(using: readerController)
        }
        return readerController
    }

    func navigateToAnchor(id: String) {
        guard !id.isEmpty else {
            return
        }

        pendingNavigationAnchorID = id
        consumePendingAnchorOnNextNavigationFinish = false

        if let readerController {
            readerController.scrollToHeading(id: id)
            pendingNavigationAnchorID = nil
        }
    }

    func navigateInCurrentWindow(to url: URL) {
        let normalizedURL = MarkdownDocumentOpener.normalizedFileURL(for: url)
        guard MarkdownDocumentOpener.supports(url: normalizedURL) else {
            return
        }

        guard fileURL != normalizedURL else {
            return
        }

        persistCurrentScrollFraction()

        let token = UUID()
        sourceLoadToken = token
        let sourceLoader = self.sourceLoader
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            do {
                let source = try sourceLoader(normalizedURL)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.sourceLoadToken == token else {
                        return
                    }

                    self.replaceCurrentFile(with: source, fileURL: normalizedURL)
                }
            } catch {
                DispatchQueue.main.async {
                    NSApp.presentError(error)
                }
            }
        }
    }

    private func replaceCurrentFile(with loadedSource: LoadedMarkdownSource, fileURL: URL) {
        self.fileURL = fileURL
        sourceText = loadedSource.sourceText
        fileFingerprint = loadedSource.fingerprint
        currentActiveHeadingID = nil
        OpenDocumentRegistry.shared.reindex(self)

        documentWindowController?.setDisplayedTitle(fileURL.lastPathComponent)
        scheduleRenderIfPossible()
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

    private static func defaultOpenMarkdownLink(_ url: URL, _ anchorID: String?) {
        do {
            try MarkdownDocumentOpener.open(url: url, anchorID: anchorID)
        } catch {
            NSApp.presentError(error)
        }
    }

    nonisolated private static func loadSource(from fileURL: URL) throws -> LoadedMarkdownSource {
        let data = try Data(contentsOf: fileURL)
        let sourceText: String
        if let decoded = String(data: data, encoding: .utf8) {
            sourceText = decoded
        } else {
            sourceText = String(decoding: data, as: UTF8.self)
        }

        return LoadedMarkdownSource(
            sourceText: sourceText,
            fingerprint: FileFingerprint.sha256Hex(for: data)
        )
    }

    private func sameDocumentAnchorID(for url: URL) -> String? {
        guard
            let currentFileURL = fileURL,
            url.isFileURL,
            let fragment = url.fragment,
            !fragment.isEmpty,
            MarkdownDocumentOpener.normalizedFileURL(for: currentFileURL) == MarkdownDocumentOpener.normalizedFileURL(for: url)
        else {
            return nil
        }

        return fragment
    }

    private func consumePendingNavigationAnchorIfNeeded(using readerController: WebKitReaderViewController?) {
        guard
            consumePendingAnchorOnNextNavigationFinish,
            let anchorID = pendingNavigationAnchorID,
            let readerController
        else {
            return
        }

        consumePendingAnchorOnNextNavigationFinish = false
        pendingNavigationAnchorID = nil
        readerController.scrollToHeading(id: anchorID)
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

struct LoadedMarkdownSource: Sendable {
    let sourceText: String
    let fingerprint: String
}
