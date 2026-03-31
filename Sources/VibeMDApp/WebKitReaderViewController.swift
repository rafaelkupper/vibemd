import AppKit
import Foundation
import VibeMDCore
import WebKit

@MainActor
class WebKitReaderViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private static let headingScrollOffset: Int = 28
    private static let activeHeadingThreshold: Int = 32

    private enum ScriptMessageName {
        static let scroll = "vibemdScroll"
        static let activeHeading = "vibemdActiveHeading"
    }

    private let localAssetSchemeHandler = WebKitLocalAssetSchemeHandler()
    private let webView: WKWebView
    private var pendingRestoreFraction: Double?
    private var lastKnownScrollFraction: Double = 0
    private(set) var currentActiveHeadingID: String?

    var onOpenLink: ((URL) -> Void)?
    var onScrollPositionChange: ((Double) -> Void)?
    var onActiveHeadingChange: ((String?) -> Void)?
    var onNavigationFinished: (() -> Void)?

    init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Self.scrollScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = contentController
        configuration.preferences.isTextInteractionEnabled = true
        configuration.setURLSchemeHandler(localAssetSchemeHandler, forURLScheme: "vibemd-local")

        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(nibName: nil, bundle: nil)

        contentController.add(self, name: ScriptMessageName.scroll)
        contentController.add(self, name: ScriptMessageName.activeHeading)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        configureScrollBehavior()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var currentScrollFraction: Double {
        lastKnownScrollFraction
    }

    var horizontalScrollElasticityForTesting: NSScrollView.Elasticity? {
        webContentScrollView()?.horizontalScrollElasticity
    }

    var hasHorizontalScrollerForTesting: Bool? {
        webContentScrollView()?.hasHorizontalScroller
    }

    static var scrollScriptSourceForTesting: String {
        scrollScript
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 760))
        view.wantsLayer = true
        view.layer?.backgroundColor = ReaderTheme.backgroundColor.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.wantsLayer = true
        webView.layer?.backgroundColor = ReaderTheme.backgroundColor.cgColor
        webView.layer?.masksToBounds = true

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        configureScrollBehavior()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.appearance = NSAppearance(named: .darkAqua)
        configureScrollBehavior()
        suppressWindowChromeArtifacts()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        configureScrollBehavior()
        suppressWindowChromeArtifacts()
    }

    func displayLoading(for fileName: String) {
        pendingRestoreFraction = nil
        webView.loadHTMLString(loadingHTML(for: fileName), baseURL: nil)
    }

    func apply(renderOutput: WebKitRenderOutput, initialScrollFraction: Double?) {
        pendingRestoreFraction = initialScrollFraction
        lastKnownScrollFraction = initialScrollFraction ?? 0
        webView.loadHTMLString(renderOutput.html, baseURL: renderOutput.baseURL)
    }

    func loadHTMLForTesting(_ html: String, baseURL: URL? = nil, initialScrollFraction: Double? = nil) {
        pendingRestoreFraction = initialScrollFraction
        lastKnownScrollFraction = initialScrollFraction ?? 0
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func evaluateJavaScriptForTesting(
        _ script: String,
        completionHandler: (@Sendable (Any?, Error?) -> Void)? = nil
    ) {
        webView.evaluateJavaScript(script, completionHandler: completionHandler)
    }

    func scrollToHeading(id: String) {
        webView.evaluateJavaScript(Self.scrollToHeadingScript(for: id))
    }

    static func scrollToHeadingScript(for id: String) -> String {
        let escapedID = id
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (function() {
          const target = document.getElementById("\(escapedID)");
          if (!target) {
            return false;
          }
          const offset = \(headingScrollOffset);
          const targetTop = window.scrollY + target.getBoundingClientRect().top - offset;
          window.scrollTo({ top: Math.max(targetTop, 0), behavior: 'auto' });
          return true;
        })();
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case ScriptMessageName.scroll:
            if let fraction = message.body as? Double {
                handleReportedScrollFraction(fraction)
            }
        case ScriptMessageName.activeHeading:
            if let headingID = message.body as? String {
                handleReportedActiveHeading(headingID.isEmpty ? nil : headingID)
            } else if message.body is NSNull {
                handleReportedActiveHeading(nil)
            }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        configureScrollBehavior()
        suppressWindowChromeArtifacts()
        restorePendingScrollIfNeeded()
        onNavigationFinished?()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard
            navigationAction.navigationType == .linkActivated,
            let url = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }

        decisionHandler(handleActivatedLink(url))
    }

    func handleActivatedLink(_ url: URL) -> WKNavigationActionPolicy {
        onOpenLink?(url)
        return .cancel
    }

    func handleReportedScrollFraction(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        lastKnownScrollFraction = clamped
        onScrollPositionChange?(clamped)
    }

    func handleReportedActiveHeading(_ headingID: String?) {
        guard currentActiveHeadingID != headingID else {
            return
        }

        currentActiveHeadingID = headingID
        onActiveHeadingChange?(headingID)
    }

    private func restorePendingScrollIfNeeded() {
        guard let fraction = pendingRestoreFraction else {
            return
        }

        pendingRestoreFraction = nil
        let clamped = min(max(fraction, 0), 1)
        let script = """
        (function() {
          const root = document.scrollingElement || document.documentElement;
          const maxOffset = Math.max(root.scrollHeight - window.innerHeight, 0);
          window.scrollTo(0, maxOffset * \(clamped));
        })();
        """
        webView.evaluateJavaScript(script)
        lastKnownScrollFraction = clamped
    }

    private func loadingHTML(for fileName: String) -> String {
        let escapedFileName = fileName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              margin: 0;
              min-height: 100%;
              background: \(ReaderTheme.backgroundHex);
              color: \(ReaderTheme.secondaryTextHex);
              font-family: \(ReaderTheme.bodyFontStack);
              font-size: 16px;
              line-height: \(ReaderTheme.bodyLineHeight);
              overflow-x: hidden;
              overscroll-behavior-x: none;
            }
            #write {
              box-sizing: border-box;
              max-width: \(ReaderTheme.contentMaxWidth)px;
              margin: 0 auto;
              padding: 0 \(ReaderTheme.contentHorizontalPadding)px 43px;
            }
          </style>
        </head>
        <body>
          <div id="write"><p>Opening \(escapedFileName)...</p></div>
        </body>
        </html>
        """
    }

    private func configureScrollBehavior() {
        let scrollViews = webContentScrollViews()
        guard !scrollViews.isEmpty else {
            return
        }

        for scrollView in scrollViews {
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.horizontalScrollElasticity = .none
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets()
            scrollView.scrollerInsets = NSEdgeInsets()
        }
    }

    private func webContentScrollView() -> NSScrollView? {
        webContentScrollViews().first
    }

    private func webContentScrollViews() -> [NSScrollView] {
        findScrollViews(in: webView)
    }

    private func findScrollViews(in view: NSView) -> [NSScrollView] {
        let localScrollViews = (view as? NSScrollView).map { [$0] } ?? []
        return localScrollViews + view.subviews.flatMap(findScrollViews(in:))
    }

    private func suppressWindowChromeArtifacts() {
        guard let window = view.window else {
            return
        }

        WindowChromeSuppression.suppress(in: window)
    }

    private static var scrollScript: String {
        """
        (function() {
          function clampHorizontalScroll() {
            if (window.scrollX !== 0) {
              window.scrollTo(0, window.scrollY);
            }
          }

          function currentFraction() {
            const root = document.scrollingElement || document.documentElement;
            const maxOffset = Math.max(root.scrollHeight - window.innerHeight, 0);
            if (maxOffset <= 0) {
              return 0;
            }
            return Math.max(0, Math.min(1, window.scrollY / maxOffset));
          }

          var pending = false;
          var pendingClamp = false;
          function report() {
            pending = false;
            clampHorizontalScroll();
            window.webkit.messageHandlers.vibemdScroll.postMessage(currentFraction());
            window.webkit.messageHandlers.vibemdActiveHeading.postMessage(currentHeadingID());
          }

          function performClamp() {
            pendingClamp = false;
            clampHorizontalScroll();
          }

          function currentHeadingID() {
            const headings = Array.from(document.querySelectorAll('#write h1[id], #write h2[id], #write h3[id], #write h4[id], #write h5[id], #write h6[id]'));
            if (headings.length === 0) {
              return null;
            }

            const threshold = \(activeHeadingThreshold);
            let active = headings[0];
            for (const heading of headings) {
              if (heading.getBoundingClientRect().top <= threshold) {
                active = heading;
              } else {
                break;
              }
            }
            return active ? active.id : null;
          }

          function scheduleReport() {
            if (pending) {
              return;
            }
            pending = true;
            requestAnimationFrame(report);
          }

          function scheduleClamp() {
            if (pendingClamp) {
              return;
            }
            pendingClamp = true;
            requestAnimationFrame(performClamp);
          }

          window.addEventListener('scroll', function() {
            scheduleClamp();
            scheduleReport();
          }, { passive: true });
          window.addEventListener('load', function() {
            scheduleClamp();
            scheduleReport();
          }, { once: true });
          window.addEventListener('resize', function() {
            scheduleClamp();
            scheduleReport();
          });
          window.addEventListener('wheel', function(event) {
            if (Math.abs(event.deltaX) > 0) {
              event.preventDefault();
              scheduleClamp();
            }
          }, { passive: false });
        })();
        """
    }
}

private final class WebKitLocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url else {
                throw NSError(
                    domain: "WebKitLocalAssetSchemeHandler",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing local asset URL."]
                )
            }
            let asset = try LocalAssetLoader.load(from: url)
            urlSchemeTask.didReceive(asset.response)
            urlSchemeTask.didReceive(asset.data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
