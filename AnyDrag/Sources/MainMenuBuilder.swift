import Cocoa

/// Builds `NSApp.mainMenu`. AnyDrag has no storyboard, so without this the
/// app has no menu bar at all — fine for a menu-bar-only accessory, but as
/// soon as the Dock icon is on (`AppIconMode.dock` / `.both`) the app is a
/// regular app and the top menu bar is shown empty. Installing the menu in
/// every mode also gives the Settings window its ⌘Q / ⌘, / ⌘C / ⌘V key
/// equivalents, which dispatch through the main menu even when it is not
/// drawn.
///
/// Rebuilt on `.anyDragLanguageChanged` by the AppDelegate; titles are read
/// through `NSLocalizedString` at build time.
enum MainMenuBuilder {

    struct Actions {
        let openSettings: Selector
        let openAbout: Selector
        let checkForUpdates: Selector
        let target: AnyObject
    }

    static func build(appName: String, actions: Actions) -> NSMenu {
        let mainMenu = NSMenu()

        // ─── App menu ───────────────────────────────────────────────
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        appMenu.addItem(targeted(NSLocalizedString("About AnyDrag", comment: ""),
                                 actions.openAbout, "", actions.target))
        appMenu.addItem(.separator())
        appMenu.addItem(targeted(NSLocalizedString("Settings…", comment: ""),
                                 actions.openSettings, ",", actions.target))
        appMenu.addItem(targeted(NSLocalizedString("Check for Updates…", comment: ""),
                                 actions.checkForUpdates, "", actions.target))
        appMenu.addItem(.separator())

        let hide = NSMenuItem(title: String(format: NSLocalizedString("menu.hideApp", comment: ""), appName),
                              action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hide)
        let hideOthers = NSMenuItem(title: NSLocalizedString("menu.hideOthers", comment: ""),
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.showAll", comment: ""),
                                   action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: NSLocalizedString("Quit AnyDrag", comment: ""),
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // ─── Edit menu (standard responder-chain selectors) ─────────
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: NSLocalizedString("menu.edit", comment: ""))
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.undo", comment: ""),
                                    action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: NSLocalizedString("menu.redo", comment: ""),
                              action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.cut", comment: ""),
                                    action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.copy", comment: ""),
                                    action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.paste", comment: ""),
                                    action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.selectAll", comment: ""),
                                    action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // ─── Window menu ────────────────────────────────────────────
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: NSLocalizedString("menu.window", comment: ""))
        windowItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.minimize", comment: ""),
                                      action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.zoom", comment: ""),
                                      action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: NSLocalizedString("menu.bringAllToFront", comment: ""),
                                      action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private static func targeted(_ title: String, _ action: Selector, _ key: String, _ target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
