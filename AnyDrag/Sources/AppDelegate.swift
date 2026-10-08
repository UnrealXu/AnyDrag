import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let log = FileLog("AppDelegate")

    private let permissionManager = PermissionManager()
    private let updateController = UpdateController()
    private var dragEngine: DragEngine?
    private var menuBarController: MenuBarController?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist says LSUIElement, so we start as an accessory (no Dock
        // icon flashes before the preference is read). Flip to a regular app
        // right away if the user chose a mode with a Dock icon (issue #52).
        applyActivationPolicy(for: Preferences.appIconMode())

        // Install the user's language override before anything reads a
        // localized string (e.g. the permission alert).
        Preferences.applyLanguageOverride()

        installMainMenu()
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageChanged(_:)),
            name: .anyDragLanguageChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appIconModeChanged(_:)),
            name: .anyDragAppIconModeChanged, object: nil)

        // Initialize analytics ASAP so the session covers the entire app
        // lifetime, including the (possibly long) wait for Accessibility
        // permission. Fires `app_launched` and any `update_installed`.
        Analytics.start()

        // Detect a launch-to-launch permission grant (false → true) and fire
        // the funnel event. We compare against the previous launch's snapshot
        // and update the stored value here so the engine's runtime trust
        // observer doesn't need to know about analytics.
        emitPermissionGrantedIfNeeded()

        Self.log.info("launch — AXIsProcessTrusted=\(AXIsProcessTrusted()) iconMode=\(Preferences.appIconMode().rawValue)")
        permissionManager.ensurePermissions { [weak self] in
            Self.log.info("permissions OK, starting")
            // The permission may have been granted *during* this launch (the
            // alert path). Re-emit so first-grant-after-install is captured.
            self?.emitPermissionGrantedIfNeeded()
            self?.startApp()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Analytics.flush()
    }

    /// Dock-icon click, and a second launch of the app from Finder /
    /// Launchpad / Spotlight (Launch Services forwards it here instead of
    /// starting a new process). With no main window, the only sensible
    /// response is the Settings window — and in every icon mode, so a user
    /// whose menu bar icon went missing (issue #52) can always get back in by
    /// opening the app again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.log.info("reopen (hasVisibleWindows=\(flag))")
        showSettings()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: NSLocalizedString("Settings…", comment: ""),
                              action: #selector(openSettings(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    private func startApp() {
        Preferences.migrateLegacyKeysIfNeeded()

        let engine = DragEngine()
        Preferences.apply(to: engine)
        engine.start()
        dragEngine = engine

        preferencesWindowController = PreferencesWindowController(
            dragEngine: engine, updateController: updateController)
        applyMenuBarIcon(for: Preferences.appIconMode(), userInitiated: false)
    }

    // MARK: - App icon mode (menu bar / Dock)

    @objc private func appIconModeChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.applyAppIconMode(Preferences.appIconMode(), userInitiated: true)
        }
    }

    private func applyAppIconMode(_ mode: AppIconMode, userInitiated: Bool) {
        Self.log.info("apply icon mode \(mode.rawValue) userInitiated=\(userInitiated)")
        let settingsWasVisible = preferencesWindowController?.isVisible ?? false
        applyActivationPolicy(for: mode)
        applyMenuBarIcon(for: mode, userInitiated: userInitiated)
        // Changing the activation policy deactivates us asynchronously (and,
        // going regular → accessory, can leave the window behind other apps
        // and the old menu bar on screen). Re-assert focus on the next run
        // loop pass, after that transition has completed.
        if settingsWasVisible {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    private func applyActivationPolicy(for mode: AppIconMode) {
        let policy: NSApplication.ActivationPolicy = mode.showsDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// Create or drop the status item to match `mode`. No-op until `startApp`
    /// has produced the engine and the Settings controller the item needs.
    private func applyMenuBarIcon(for mode: AppIconMode, userInitiated: Bool) {
        guard let engine = dragEngine, let prefs = preferencesWindowController else { return }
        if mode.showsMenuBarIcon {
            if menuBarController == nil {
                menuBarController = MenuBarController(
                    dragEngine: engine, updateController: updateController,
                    preferencesWindowController: prefs)
            }
            if userInitiated { menuBarController?.forceVisible() }
        } else {
            menuBarController = nil
        }
    }

    // MARK: - Main menu

    private func installMainMenu() {
        NSApp.mainMenu = MainMenuBuilder.build(
            appName: "AnyDrag",
            actions: .init(openSettings: #selector(openSettings(_:)),
                           openAbout: #selector(openAbout(_:)),
                           checkForUpdates: #selector(checkForUpdates(_:)),
                           target: self))
    }

    @objc private func languageChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.installMainMenu() }
    }

    @objc private func openSettings(_ sender: Any?) { showSettings() }
    @objc private func openAbout(_ sender: Any?)    { showSettings(page: .about) }
    @objc private func checkForUpdates(_ sender: Any?) { updateController.checkForUpdates(sender) }

    private func showSettings(page: SettingsPage? = nil) {
        // Before permissions are granted the Settings controller doesn't exist
        // yet; the permission alert is already the thing on screen.
        preferencesWindowController?.show(page: page)
    }

    /// Fires `permission_granted` once on the launch where the trust state
    /// flips false → true *with an observable prior state*. Idempotent.
    ///
    /// We deliberately do NOT fire when the key is absent: an already-authorized
    /// user upgrading to this integration would otherwise produce a spurious
    /// first-grant event. On absence we just record the snapshot and wait for
    /// a real transition next time. For the fresh-install flow, the launch
    /// path calls this twice — first before `ensurePermissions` (records
    /// `false` if not granted), then again after the user grants in the
    /// alert flow (sees the stored `false`, fires the event).
    private func emitPermissionGrantedIfNeeded() {
        let d = UserDefaults.standard
        let current = AXIsProcessTrusted()
        let priorObject = d.object(forKey: Preferences.Key.lastPermissionGranted)
        let hadPrior = (priorObject != nil)
        let prior = (priorObject as? Bool) ?? false
        if hadPrior && current && !prior {
            Analytics.trackPermissionGranted()
        }
        if !hadPrior || prior != current {
            d.set(current, forKey: Preferences.Key.lastPermissionGranted)
        }
    }
}
