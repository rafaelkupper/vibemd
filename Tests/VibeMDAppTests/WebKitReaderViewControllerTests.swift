import AppKit
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

@MainActor
final class WebKitReaderViewControllerTests: XCTestCase {
    func testShowFindInterfaceRevealsFindBar() {
        let controller = WebKitReaderViewController()
        let window = hostInWindow(controller)
        defer { window.close() }

        controller.showFindInterface(nil)

        XCTAssertTrue(controller.isFindBarVisibleForTesting)
    }

    func testFindCommandsRecordDirectionAndQuery() {
        let controller = WebKitReaderViewController()
        let window = hostInWindow(controller)
        defer { window.close() }

        controller.setSuppressFindExecutionForTesting(true)
        controller.setFindQueryForTesting("Heading")
        controller.findNextMatch(nil)
        controller.findPreviousMatch(nil)

        XCTAssertEqual(controller.lastFindQueryForTesting, "Heading")
        XCTAssertEqual(controller.lastFindDirectionForTesting, "previous")
    }

    func testValidateUserInterfaceItemReflectsQueryAvailability() {
        let controller = WebKitReaderViewController()
        let window = hostInWindow(controller)
        defer { window.close() }

        XCTAssertTrue(controller.validateUserInterfaceItem(makeMenuItem(action: #selector(WebKitReaderViewController.showFindInterface(_:)))))
        XCTAssertFalse(controller.validateUserInterfaceItem(makeMenuItem(action: #selector(WebKitReaderViewController.findNextMatch(_:)))))

        controller.setFindQueryForTesting("Heading")

        XCTAssertTrue(controller.validateUserInterfaceItem(makeMenuItem(action: #selector(WebKitReaderViewController.findNextMatch(_:)))))
    }

    func testIncrementalFindReportsMissingMatches() {
        let controller = WebKitReaderViewController()
        let window = hostInWindow(controller)
        defer { window.close() }

        controller.setSuppressFindExecutionForTesting(true)
        controller.setSuppressedFindMatchResultForTesting(false)
        controller.setFindQueryForTesting("absent-text")
        controller.triggerFindQueryChangeForTesting()

        XCTAssertEqual(controller.lastFindMatchFoundForTesting, false)
        XCTAssertEqual(controller.findStatusTextForTesting, "No matches")
    }

    func testIncrementalFindFindsExistingText() {
        let controller = WebKitReaderViewController()
        let window = hostInWindow(controller)
        defer { window.close() }

        controller.setSuppressFindExecutionForTesting(true)
        controller.setSuppressedFindMatchResultForTesting(true)
        controller.setFindQueryForTesting("Hello")
        controller.triggerFindQueryChangeForTesting()

        XCTAssertEqual(controller.lastFindMatchFoundForTesting, true)
        XCTAssertEqual(controller.findStatusTextForTesting, "")
    }

    func testDisplayLoadingShowsPlaceholderHTML() {
        let controller = WebKitReaderViewController()
        let window = hostInWindow(controller)
        defer { window.close() }

        waitForNavigation(in: controller) {
            controller.displayLoading(for: "Preview.md")
        }

        let bodyText = evaluateString(
            "document.getElementById('write').innerText",
            in: controller
        ) as? String

        XCTAssertTrue(bodyText?.contains("Opening Preview.md...") == true)
    }

    func testApplyLoadsRenderedHTMLContent() {
        let controller = WebKitReaderViewController()
        let window = hostInWindow(controller)
        defer { window.close() }

        let html = htmlDocument(body: "<h1>Rendered</h1><p>Body</p>")
        waitForNavigation(in: controller) {
            controller.apply(renderOutput: WebKitRenderOutput(html: html, baseURL: nil), initialScrollFraction: nil)
        }

        let heading = evaluateString(
            "document.querySelector('h1').textContent",
            in: controller
        ) as? String

        XCTAssertEqual(heading, "Rendered")
    }

    func testApplySeedsCurrentScrollFractionFromInitialValue() {
        let controller = WebKitReaderViewController()
        controller.apply(
            renderOutput: WebKitRenderOutput(html: htmlDocument(body: longScrollableBody()), baseURL: nil),
            initialScrollFraction: 0.5
        )

        XCTAssertEqual(controller.currentScrollFraction, 0.5, accuracy: 0.0001)
    }

    func testScrollScriptUsesMutablePendingFlag() {
        XCTAssertTrue(WebKitReaderViewController.scrollScriptSourceForTesting.contains("var pending = false;"))
        XCTAssertFalse(WebKitReaderViewController.scrollScriptSourceForTesting.contains("let pending = false;"))
        XCTAssertTrue(WebKitReaderViewController.scrollScriptSourceForTesting.contains("vibemdActiveHeading"))
        XCTAssertTrue(WebKitReaderViewController.scrollScriptSourceForTesting.contains("window.scrollX !== 0"))
        XCTAssertTrue(WebKitReaderViewController.scrollScriptSourceForTesting.contains("event.deltaX"))
    }

    func testReportedScrollFractionUpdatesStateAndNotifiesObservers() {
        let controller = WebKitReaderViewController()
        let scrollExpectation = expectation(description: "scroll callback")
        controller.onScrollPositionChange = { fraction in
            if fraction == 0.85 {
                scrollExpectation.fulfill()
            }
        }

        controller.handleReportedScrollFraction(0.85)

        wait(for: [scrollExpectation], timeout: 5)
        XCTAssertEqual(controller.currentScrollFraction, 0.85, accuracy: 0.0001)
    }

    func testReportedActiveHeadingUpdatesStateAndNotifiesObservers() {
        let controller = WebKitReaderViewController()
        let headingExpectation = expectation(description: "heading callback")
        controller.onActiveHeadingChange = { headingID in
            if headingID == "section-two" {
                headingExpectation.fulfill()
            }
        }

        controller.handleReportedActiveHeading("section-two")

        wait(for: [headingExpectation], timeout: 5)
        XCTAssertEqual(controller.currentActiveHeadingID, "section-two")
    }

    func testScrollToHeadingBuildsAnchorScrollScript() {
        let script = WebKitReaderViewController.scrollToHeadingScript(for: #"deep"section"#)

        XCTAssertTrue(script.contains(#"document.getElementById("deep\"section")"#))
        XCTAssertTrue(script.contains("window.scrollTo"))
        XCTAssertTrue(script.contains("const offset = 28;"))
        XCTAssertFalse(script.contains("scrollIntoView"))
    }

    func testHandleActivatedLinkForwardsExternalMarkdownAndOtherFileURLs() {
        let controller = WebKitReaderViewController()
        let expectedURLs = [
            URL(string: "https://example.com")!,
            URL(fileURLWithPath: "/tmp/docs/Guide.md"),
            URL(fileURLWithPath: "/tmp/docs/notes.txt"),
        ]
        var forwardedURLs: [URL] = []
        controller.onOpenLink = { forwardedURLs.append($0) }

        let policies = expectedURLs.map { controller.handleActivatedLink($0) }

        XCTAssertEqual(policies, Array(repeating: .cancel, count: expectedURLs.count))
        XCTAssertEqual(forwardedURLs.count, expectedURLs.count)
        XCTAssertEqual(forwardedURLs[0].scheme, expectedURLs[0].scheme)
        XCTAssertEqual(forwardedURLs[0].host, expectedURLs[0].host)
        XCTAssertEqual(normalizedPath(forwardedURLs[0]), normalizedPath(expectedURLs[0]))
        XCTAssertEqual(forwardedURLs[1].standardizedFileURL, expectedURLs[1].standardizedFileURL)
        XCTAssertEqual(forwardedURLs[2].standardizedFileURL, expectedURLs[2].standardizedFileURL)
    }

    private func waitForNavigation(
        in controller: WebKitReaderViewController,
        settleDelay: TimeInterval = 0.05,
        action: () -> Void
    ) {
        let expectation = expectation(description: "navigation finished")
        controller.onNavigationFinished = {
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
                expectation.fulfill()
            }
        }
        action()
        wait(for: [expectation], timeout: 5)
        controller.onNavigationFinished = nil
    }

    private func evaluateString(_ script: String, in controller: WebKitReaderViewController) -> Any? {
        let state = JavaScriptEvaluationState()
        let expectation = expectation(description: "evaluate js")
        controller.evaluateJavaScriptForTesting(script) { value, error in
            state.result = value
            state.receivedError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertNil(state.receivedError)
        return state.result
    }

    private func evaluateDouble(_ script: String, in controller: WebKitReaderViewController) -> Double? {
        let value = evaluateString(script, in: controller)
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return value as? Double
    }

    private func htmlDocument(body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            html, body { margin: 0; min-height: 100%; background: #383E44; color: #BCC3CA; }
            body { font: 16px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; }
            #write { max-width: 900px; margin: 0 auto; padding: 0 24px 24px; }
            p { margin: 0 0 16px; }
            img { display: block; max-width: 100%; }
          </style>
        </head>
        <body>
          <div id="write">\(body)</div>
        </body>
        </html>
        """
    }

    private func longScrollableBody() -> String {
        (0..<200).map { "<p>Paragraph \($0) with enough content to produce a scrollable page in WebKit.</p>" }.joined()
    }

    private func normalizedPath(_ url: URL?) -> String {
        let path = url?.path ?? ""
        return path.isEmpty ? "/" : path
    }

    private func makeMenuItem(action: Selector) -> NSMenuItem {
        NSMenuItem(title: "Find", action: action, keyEquivalent: "")
    }
}

private final class JavaScriptEvaluationState: @unchecked Sendable {
    var result: Any?
    var receivedError: Error?
}
