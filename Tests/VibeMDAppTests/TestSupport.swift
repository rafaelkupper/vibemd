import AppKit
import Foundation
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

@MainActor
final class RecordingReaderViewController: WebKitReaderViewController {
    var displayedLoadingNames: [String] = []
    var appliedOutputs: [WebKitRenderOutput] = []
    var appliedInitialScrollFractions: [Double?] = []
    var stubbedCurrentScrollFraction: Double = 0
    var scrolledHeadingIDs: [String] = []

    override var currentScrollFraction: Double {
        stubbedCurrentScrollFraction
    }

    override func displayLoading(for fileName: String) {
        displayedLoadingNames.append(fileName)
    }

    override func apply(renderOutput: WebKitRenderOutput, initialScrollFraction: Double?) {
        appliedOutputs.append(renderOutput)
        appliedInitialScrollFractions.append(initialScrollFraction)
    }

    override func scrollToHeading(id: String) {
        scrolledHeadingIDs.append(id)
    }
}

struct TemporaryTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createFile(named name: String, contents: Data) throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try contents.write(to: fileURL)
        return fileURL
    }

    func createTextFile(named name: String, contents: String) throws -> URL {
        try createFile(named: name, contents: Data(contents.utf8))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
func hostInWindow(_ controller: NSViewController, size: NSSize = NSSize(width: 900, height: 700)) -> NSWindow {
    controller.loadViewIfNeeded()
    controller.view.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentViewController = controller
    window.makeKeyAndOrderFront(nil)
    return window
}

func tinyPNGData() -> Data {
    Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO1+v1gAAAAASUVORK5CYII="
    )!
}
