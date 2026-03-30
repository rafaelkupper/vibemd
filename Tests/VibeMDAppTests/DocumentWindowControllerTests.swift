import AppKit
import XCTest
@testable import VibeMDApp

@MainActor
final class DocumentWindowControllerTests: XCTestCase {
    func testInitialFrameCentersWindowWithoutCascadeSource() {
        let visibleFrame = NSRect(x: 100, y: 80, width: 1600, height: 1000)
        let contentSize = DocumentWindowController.initialContentSize

        let frame = DocumentWindowController.initialFrame(
            contentSize: contentSize,
            visibleFrame: visibleFrame,
            cascadeFrom: nil
        )

        XCTAssertEqual(frame.origin.x, visibleFrame.midX - (contentSize.width / 2), accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, visibleFrame.midY - (contentSize.height / 2), accuracy: 0.5)
    }

    func testInitialFrameCascadesDownAndRightFromSourceWindow() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let contentSize = DocumentWindowController.initialContentSize
        let sourceFrame = NSRect(x: 300, y: 200, width: contentSize.width, height: contentSize.height)

        let frame = DocumentWindowController.initialFrame(
            contentSize: contentSize,
            visibleFrame: visibleFrame,
            cascadeFrom: sourceFrame
        )

        XCTAssertEqual(frame.origin.x, sourceFrame.minX + DocumentWindowController.cascadeOffset, accuracy: 0.5)
        XCTAssertEqual(frame.origin.y, sourceFrame.minY - DocumentWindowController.cascadeOffset, accuracy: 0.5)
    }
}
