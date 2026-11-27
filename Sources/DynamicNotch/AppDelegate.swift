import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
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
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Dynamic Notch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
