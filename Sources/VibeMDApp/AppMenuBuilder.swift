import AppKit

@MainActor
enum AppMenuBuilder {
    static func makeMainMenu(windowsMenu: NSMenu, appDelegate: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

        let appItem = NSMenuItem()
        let fileItem = NSMenuItem()
        let windowItem = NSMenuItem()

        mainMenu.addItem(appItem)
        mainMenu.addItem(fileItem)
        mainMenu.addItem(windowItem)

        appItem.submenu = appMenu()
        fileItem.submenu = fileMenu(appDelegate: appDelegate)
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
}
