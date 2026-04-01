import AppKit
import XCTest
@testable import VibeMDApp

@MainActor
final class AppMenuBuilderTests: XCTestCase {
    func testMainMenuIncludesEditMenuWithFindCommands() throws {
        let appDelegate = AppDelegate(openURLs: { _ in })
        let windowMenu = NSMenu(title: "Window")

        let menu = AppMenuBuilder.makeMainMenu(windowsMenu: windowMenu, appDelegate: appDelegate)

        XCTAssertEqual(menu.items.count, 4)
        XCTAssertEqual(menu.items[0].submenu?.title, "VibeMD")
        XCTAssertEqual(menu.items[1].submenu?.title, "File")
        XCTAssertEqual(menu.items[2].submenu?.title, "Edit")
        XCTAssertTrue(menu.items[3].submenu === windowMenu)

        let editMenu = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(editMenu.items.map(\.title), ["Find…", "Find Next", "Find Previous"])

        let findItem = try XCTUnwrap(editMenu.items.first)
        XCTAssertEqual(findItem.action, #selector(WebKitReaderViewController.showFindInterface(_:)))
        XCTAssertNil(findItem.target)
        XCTAssertEqual(findItem.keyEquivalent, "f")
        XCTAssertEqual(findItem.keyEquivalentModifierMask, [.command])

        let nextItem = editMenu.items[1]
        XCTAssertEqual(nextItem.action, #selector(WebKitReaderViewController.findNextMatch(_:)))
        XCTAssertEqual(nextItem.keyEquivalent, "g")
        XCTAssertEqual(nextItem.keyEquivalentModifierMask, [.command])

        let previousItem = editMenu.items[2]
        XCTAssertEqual(previousItem.action, #selector(WebKitReaderViewController.findPreviousMatch(_:)))
        XCTAssertEqual(previousItem.keyEquivalent, "G")
        XCTAssertEqual(previousItem.keyEquivalentModifierMask, [.command, .shift])
    }
}
