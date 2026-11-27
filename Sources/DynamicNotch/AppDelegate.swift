import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        quitOtherCopies()
        panel = NotchPanelController()
        panel?.show()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Notch")
        item.menu = AppMenu.build(openSettings: { [weak self] in self?.openSettings() })
        statusItem = item

        // Start every monitor. Each one reports into IslandModel.shared.
        MusicProvider.shared.start()
        PrivacyMonitor.shared.start()
        BatteryMonitor.shared.start()
        BluetoothMonitor.shared.start()
        AudioMonitor.shared.start()
        LockMonitor.shared.start()
        DownloadsMonitor.shared.start()
        DebugHooks.installIfEnabled()

        applyAppearancePrefs()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearancePrefs() }
        }

        // First launch always shows Settings once; after that only if "Start minimized" is off.
        if !Prefs.on(Prefs.didFirstLaunch) || !Prefs.on(Prefs.startMinimized) {
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

    private func applyAppearancePrefs() {
        let dock = Prefs.on(Prefs.showDockIcon)
        let policy: NSApplication.ActivationPolicy = dock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            // Switching back to accessory hides open windows; keep Settings in front.
            if !dock, settingsWindow != nil {
                DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true); self.settingsWindow?.makeKeyAndOrderFront(nil) }
            }
        }
        statusItem?.isVisible = Prefs.on(Prefs.showMenuBarIcon)
    }

    /// Only one island at a time: a newly started copy replaces an older one.
    private func quitOtherCopies() {
        let me = NSRunningApplication.current
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where other.processIdentifier != me.processIdentifier {
            other.terminate()
        }
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

        let timerItem = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for minutes in [1, 3, 5, 10, 15, 20, 30, 45, 60] {
            timerMenu.addItem(ClosureMenuItem("\(minutes) min") { timers.start(seconds: TimeInterval(minutes * 60)) })
        }
        timerMenu.addItem(.separator())
        timerMenu.addItem(ClosureMenuItem("Custom…") { askCustomTimer() })
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        if timers.isActive {
            menu.addItem(ClosureMenuItem(timers.isPaused ? "Resume Timer" : "Pause Timer") { timers.togglePause() })
            menu.addItem(ClosureMenuItem("Cancel Timer") { timers.cancel() })
        }

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
