import AppKit

@MainActor
enum AppMenuBuilder {
    static func makeMainMenu(windowsMenu: NSMenu, appDelegate: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

        let appItem = NSMenuItem()
        let fileItem = NSMenuItem()
        let editItem = NSMenuItem()
        let windowItem = NSMenuItem()

        mainMenu.addItem(appItem)
        mainMenu.addItem(fileItem)
        mainMenu.addItem(editItem)
        mainMenu.addItem(windowItem)

        appItem.submenu = appMenu()
        fileItem.submenu = fileMenu(appDelegate: appDelegate)
        editItem.submenu = editMenu()
        windowItem.submenu = windowsMenu

        return mainMenu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "VibeMD")
        menu.addItem(
            withTitle: "Quit VibeMD",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    private static func fileMenu(appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "File")

        let openItem = NSMenuItem(
            title: "Open...",
            action: #selector(AppDelegate.openDocument(_:)),
            keyEquivalent: "o"
        )
        openItem.target = appDelegate
        menu.addItem(openItem)

        let closeItem = NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = nil
        menu.addItem(closeItem)

        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(findMenuItem(
            title: "Find…",
            keyEquivalent: "f",
            modifiers: [.command],
            action: #selector(WebKitReaderViewController.showFindInterface(_:))
        ))
        menu.addItem(findMenuItem(
            title: "Find Next",
            keyEquivalent: "g",
            modifiers: [.command],
            action: #selector(WebKitReaderViewController.findNextMatch(_:))
        ))
        menu.addItem(findMenuItem(
            title: "Find Previous",
            keyEquivalent: "G",
            modifiers: [.command, .shift],
            action: #selector(WebKitReaderViewController.findPreviousMatch(_:))
        ))
        return menu
    }

    private static func findMenuItem(
        title: String,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.target = nil
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
