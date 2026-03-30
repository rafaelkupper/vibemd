import AppKit
import XCTest
@testable import VibeMDApp

@MainActor
final class AppDelegateTests: XCTestCase {
    func testApplicationOpenFileReturnsTrueAndForwardsSupportedURL() {
        var opened: [URL] = []
        let delegate = AppDelegate(
            openURLs: { opened.append(contentsOf: $0) },
            supportsURL: { $0.pathExtension == "md" }
        )

        let result = delegate.application(NSApplication.shared, openFile: "/tmp/docs/Guide.md")

        XCTAssertTrue(result)
        XCTAssertEqual(opened, [URL(fileURLWithPath: "/tmp/docs/Guide.md")])
    }

    func testApplicationOpenFileReturnsFalseForUnsupportedURL() {
        var opened: [URL] = []
        let delegate = AppDelegate(
            openURLs: { opened.append(contentsOf: $0) },
            supportsURL: { _ in false }
        )

        let result = delegate.application(NSApplication.shared, openFile: "/tmp/docs/Guide.txt")

        XCTAssertFalse(result)
        XCTAssertTrue(opened.isEmpty)
    }

    func testApplicationOpenFilesFiltersUnsupportedEntries() {
        var opened: [URL] = []
        let delegate = AppDelegate(
            openURLs: { opened.append(contentsOf: $0) },
            supportsURL: { $0.pathExtension.lowercased() == "md" }
        )

        delegate.application(
            NSApplication.shared,
            openFiles: ["/tmp/docs/One.md", "/tmp/docs/Two.txt", "/tmp/docs/Three.MD"]
        )

        XCTAssertEqual(
            opened,
            [
                URL(fileURLWithPath: "/tmp/docs/One.md"),
                URL(fileURLWithPath: "/tmp/docs/Three.MD"),
            ]
        )
    }

    func testApplicationOpenURLsForwardsAllValues() {
        var opened: [URL] = []
        let delegate = AppDelegate(openURLs: { opened.append(contentsOf: $0) })
        let urls = [
            URL(fileURLWithPath: "/tmp/docs/One.md"),
            URL(fileURLWithPath: "/tmp/docs/Two.md"),
        ]

        delegate.application(NSApplication.shared, open: urls)

        XCTAssertEqual(opened, urls)
    }
}
