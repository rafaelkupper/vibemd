import AppKit
import Foundation
import UniformTypeIdentifiers
import VibeMDCore
import WebKit

@MainActor
class WebKitReaderViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private enum ScriptMessageName {
        static let scroll = "vibemdScroll"
    }

    private let localAssetSchemeHandler = WebKitLocalAssetSchemeHandler()
    private let webView: WKWebView
    private var pendingRestoreFraction: Double?
    private var lastKnownScrollFraction: Double = 0

    var onOpenLink: ((URL) -> Void)?
    var onScrollPositionChange: ((Double) -> Void)?
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
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var currentScrollFraction: Double {
        lastKnownScrollFraction
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

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.appearance = NSAppearance(named: .darkAqua)
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
        completionHandler: ((Any?, Error?) -> Void)? = nil
    ) {
        webView.evaluateJavaScript(script, completionHandler: completionHandler)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case ScriptMessageName.scroll:
            if let fraction = message.body as? Double {
                handleReportedScrollFraction(fraction)
            }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

    private static var scrollScript: String {
        """
        (function() {
          function currentFraction() {
            const root = document.scrollingElement || document.documentElement;
            const maxOffset = Math.max(root.scrollHeight - window.innerHeight, 0);
            if (maxOffset <= 0) {
              return 0;
            }
            return Math.max(0, Math.min(1, window.scrollY / maxOffset));
          }

          var pending = false;
          function report() {
            pending = false;
            window.webkit.messageHandlers.vibemdScroll.postMessage(currentFraction());
          }

          function scheduleReport() {
            if (pending) {
              return;
            }
            pending = true;
            requestAnimationFrame(report);
          }

          window.addEventListener('scroll', scheduleReport, { passive: true });
          window.addEventListener('load', scheduleReport, { once: true });
          window.addEventListener('resize', scheduleReport);
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
