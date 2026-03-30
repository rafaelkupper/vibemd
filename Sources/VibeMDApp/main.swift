import AppKit

let application = NSApplication.shared
let appDelegate = AppDelegate()
let windowsMenu = NSMenu(title: "Window")

application.setActivationPolicy(.regular)
application.delegate = appDelegate
application.mainMenu = AppMenuBuilder.makeMainMenu(
    windowsMenu: windowsMenu,
    appDelegate: appDelegate
)
application.windowsMenu = windowsMenu
application.activate(ignoringOtherApps: true)
application.run()
