import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var launchedAtLogin = false
    private var iconsWereHidden = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // macOS marks the launch event when it starts the app as a login item.
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        let replacedRunningCopy = quitOtherCopies()
        panel = NotchPanelController()
        panel?.show()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Notch")
        item.menu = AppMenu.build(openSettings: { [weak self] in self?.openSettings() })
        statusItem = item

        // Start every monitor. Each one reports into IslandModel.shared.
        AlarmProvider.shared.start()
        MusicProvider.shared.start()
        PrivacyMonitor.shared.start()
        BatteryMonitor.shared.start()
        BluetoothMonitor.shared.start()
        AudioMonitor.shared.start()
        LockMonitor.shared.start()
        DownloadsMonitor.shared.start()
        DebugHooks.installIfEnabled()

        iconsWereHidden = iconsHidden
        applyAppearancePrefs()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearancePrefs() }
        }

        // Settings opens at launch: the first time ever; when "Start minimized" is off; and
        // whenever the user started the app by hand while it has no visible icon (or was
        // already running) — otherwise opening it would look like nothing happened.
        let opensByHand = !launchedAtLogin && (iconsHidden || replacedRunningCopy)
        if !Prefs.on(Prefs.didFirstLaunch) || !Prefs.on(Prefs.startMinimized) || opensByHand {
            UserDefaults.standard.set(true, forKey: Prefs.didFirstLaunch)
            openSettings()
        }
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows Settings — the way back in when
    /// both icons are hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private var applyingPrefs = false
    private var appliedMenuBarIcon: Bool?

    /// Called on every UserDefaults change. Changing the status item itself writes to
    /// UserDefaults too, so this must only act on real changes and never re-enter
    /// (re-entering crashed the app with endless recursion).
    private func applyAppearancePrefs() {
        guard !applyingPrefs else { return }
        applyingPrefs = true
        defer { applyingPrefs = false }

        let dock = Prefs.on(Prefs.showDockIcon)
        let policy: NSApplication.ActivationPolicy = dock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            // Switching back to accessory hides open windows; keep Settings in front.
            if !dock, settingsWindow != nil {
                DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true); self.settingsWindow?.makeKeyAndOrderFront(nil) }
            }
        }
        // Only touch the icon when our own setting changed, so hiding it in System Settings
        // (Menu Bar) isn't overridden.
        let menuIcon = Prefs.on(Prefs.showMenuBarIcon)
        if menuIcon != appliedMenuBarIcon {
            appliedMenuBarIcon = menuIcon
            statusItem?.isVisible = menuIcon
        }

        let hidden = iconsHidden
        if hidden && !iconsWereHidden {
            iconsWereHidden = true
            // After the current change finishes, not inside the notification.
            DispatchQueue.main.async { self.explainHiddenIcons() }
        }
        iconsWereHidden = hidden
    }

    private var iconsHidden: Bool { !Prefs.on(Prefs.showMenuBarIcon) && !Prefs.on(Prefs.showDockIcon) }

    /// With no Dock or menu bar icon the app has no visible handle, so say how to get back.
    private func explainHiddenIcons() {
        let alert = NSAlert()
        alert.messageText = "Dynamic Notch keeps running"
        alert.informativeText = "There's no icon in the menu bar or Dock now. To open Settings again, open Dynamic Notch from Applications, Launchpad or Spotlight, or right-click the island."
        alert.addButton(withTitle: "OK")
        if let window = settingsWindow, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// Only one island at a time: a newly started copy replaces an older one.
    /// Returns true when another copy was running.
    private func quitOtherCopies() -> Bool {
        let me = NSRunningApplication.current
        var found = false
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where other.processIdentifier != me.processIdentifier {
            other.terminate()
            found = true
        }
        return found
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: SettingsViewController())
            window.title = "Dynamic Notch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    /// Drop the Settings window when it closes so its views don't stay in memory.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        DispatchQueue.main.async { self.settingsWindow = nil }
    }
}

/// The menu shown from the menu bar icon and when right-clicking the island.
@MainActor
enum AppMenu {
    private static var openSettingsHandler: (() -> Void)?

    static func build(openSettings: @escaping () -> Void) -> NSMenu {
        openSettingsHandler = openSettings
        let menu = NSMenu()
        menu.delegate = MenuRefresher.shared
        fill(menu)
        return menu
    }

    static func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        let timers = TimerProvider.shared
        let stopwatch = StopwatchProvider.shared
        let recorder = RecorderProvider.shared

        let alarms = AlarmProvider.shared
        let timerItem = NSMenuItem(title: "New Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for minutes in [1, 3, 5, 10, 15, 20, 30, 45, 60] {
            timerMenu.addItem(ClosureMenuItem("\(minutes) min") { timers.start(seconds: TimeInterval(minutes * 60)) })
        }
        timerMenu.addItem(.separator())
        timerMenu.addItem(ClosureMenuItem("Custom…") { askCustomTimer() })
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        for timer in timers.ordered {
            let item = NSMenuItem(title: "Timer \(timer.label)\(timer.isPaused ? " (paused)" : "")", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(ClosureMenuItem(timer.isPaused ? "Resume" : "Pause") { timers.togglePause(timer.id) })
            sub.addItem(ClosureMenuItem("Cancel") { timers.cancel(timer.id) })
            item.submenu = sub
            menu.addItem(item)
        }

        let alarmItem = NSMenuItem(title: "Alarms", action: nil, keyEquivalent: "")
        let alarmMenu = NSMenu()
        alarmMenu.addItem(ClosureMenuItem("Add Alarm…") { alarms.askNewAlarm() })
        if !alarms.alarms.isEmpty { alarmMenu.addItem(.separator()) }
        for alarm in alarms.alarms {
            let item = NSMenuItem(title: alarm.date.formatted(date: .abbreviated, time: .shortened), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(ClosureMenuItem("Delete") { alarms.remove(alarm.id) })
            item.submenu = sub
            alarmMenu.addItem(item)
        }
        alarmItem.submenu = alarmMenu
        menu.addItem(alarmItem)

        if stopwatch.isActive {
            menu.addItem(ClosureMenuItem(stopwatch.isRunning ? "Stop Stopwatch" : "Resume Stopwatch") { stopwatch.toggle() })
            menu.addItem(ClosureMenuItem("Reset Stopwatch") { stopwatch.reset() })
        } else {
            menu.addItem(ClosureMenuItem("Start Stopwatch") { stopwatch.toggle() })
        }

        menu.addItem(ClosureMenuItem(recorder.isRecording ? "Stop Voice Memo" : "Record Voice Memo") { recorder.toggle() })
        menu.addItem(ClosureMenuItem("Open Voice Memos Folder") { recorder.revealFolder() })

        menu.addItem(.separator())
        let model = IslandModel.shared
        if model.hidden {
            menu.addItem(ClosureMenuItem("Show Activities") { model.setHidden(false) })
        } else if model.primary != nil {
            menu.addItem(ClosureMenuItem("Hide Activities") { model.setHidden(true) })
        }
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { openSettingsHandler?() })
        menu.addItem(ClosureMenuItem("Quit Dynamic Notch", key: "q") { NSApp.terminate(nil) })
    }

    static func popUpAtMouse() {
        let menu = NSMenu()
        fill(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func askCustomTimer() {
        let alert = NSAlert()
        alert.messageText = "Custom Timer"
        alert.informativeText = "Minutes (decimals allowed, e.g. 2.5):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "25"
        alert.accessoryView = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn,
           let minutes = Double(field.stringValue.replacingOccurrences(of: ",", with: ".")), minutes > 0 {
            TimerProvider.shared.start(seconds: minutes * 60)
        }
    }
}

/// Rebuilds the status menu each time it opens so its items match the current state.
@MainActor
final class MenuRefresher: NSObject, NSMenuDelegate {
    static let shared = MenuRefresher()
    func menuNeedsUpdate(_ menu: NSMenu) { AppMenu.fill(menu) }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
