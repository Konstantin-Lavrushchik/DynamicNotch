import AppKit
import ServiceManagement

enum Prefs {
    static let expandOnHover = "expandOnHover"
    static let haptics = "haptics"
    static let showMusic = "showMusic"
    static let showCharging = "showCharging"
    static let showHeadphones = "showHeadphones"
    static let showSilent = "showSilent"
    static let showVolume = "showVolume"
    static let showUnlock = "showUnlock"
    static let showDownloads = "showDownloads"
    static let showPrivacy = "showPrivacy"
    static let showDockIcon = "showDockIcon"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let startMinimized = "startMinimized"
    static let didFirstLaunch = "didFirstLaunch"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            expandOnHover: false,
            haptics: true,
            showMusic: true,
            showCharging: true,
            showHeadphones: true,
            showSilent: true,
            showVolume: true,
            showUnlock: true,
            showDownloads: true,
            showPrivacy: true,
            showDockIcon: false,
            showMenuBarIcon: true,
            startMinimized: true,
            didFirstLaunch: false,
        ])
    }

    static func on(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
}

/// Settings in plain AppKit: a SwiftUI Form costs ~15 MB more memory while it is open.
@MainActor
final class SettingsViewController: NSViewController {
    private var loginBox: NSButton?
    private let note = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        func header(_ title: String) {
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: 13)
            if !stack.arrangedSubviews.isEmpty { stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!) }
            stack.addArrangedSubview(label)
        }
        func toggle(_ title: String, _ key: String) {
            let box = PrefCheckbox(title: title, key: key)
            stack.addArrangedSubview(box)
        }
        func caption(_ text: String) {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 380
            stack.addArrangedSubview(label)
        }

        header("App")
        let login = NSButton(checkboxWithTitle: "Open at login", target: self, action: #selector(toggleLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginBox = login
        stack.addArrangedSubview(login)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .systemOrange
        note.isHidden = true
        stack.addArrangedSubview(note)
        toggle("Start minimized (no window at launch)", Prefs.startMinimized)
        toggle("Show icon in the Dock", Prefs.showDockIcon)
        toggle("Show icon in the menu bar", Prefs.showMenuBarIcon)
        caption("With both icons hidden: right-click the island, or open Dynamic Notch again from Applications.")

        header("Island")
        toggle("Expand when the pointer rests on the island", Prefs.expandOnHover)
        caption("Off = iPhone behaviour: press and hold to expand, click to open the app, swipe up to collapse, swipe sideways to hide.")
        toggle("Trackpad haptic when the island expands", Prefs.haptics)

        header("Live Activities")
        toggle("Now Playing (Music, Spotify)", Prefs.showMusic)
        toggle("Downloads", Prefs.showDownloads)
        toggle("Microphone and camera dots", Prefs.showPrivacy)

        header("Alerts")
        toggle("Charging and low battery", Prefs.showCharging)
        toggle("AirPods and headphones", Prefs.showHeadphones)
        toggle("Silent mode (sound muted)", Prefs.showSilent)
        toggle("Volume", Prefs.showVolume)
        toggle("Unlock", Prefs.showUnlock)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let footer = NSStackView(views: [
            NSTextField(labelWithString: "Dynamic Notch \(version)"),
            NSButton(title: "GitHub", target: self, action: #selector(openGitHub)),
            NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:))),
        ])
        footer.spacing = 10
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(footer)

        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 430),
        ])
        view = container
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                show("Allow Dynamic Notch in System Settings → General → Login Items.")
            } else {
                note.isHidden = true
            }
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            show("Couldn't change it: \(error.localizedDescription)")
        }
    }

    private func show(_ text: String) {
        note.stringValue = text
        note.isHidden = false
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/Konstantin-Lavrushchik/DynamicNotch") { NSWorkspace.shared.open(url) }
    }
}

/// A checkbox that reads and writes one Bool in UserDefaults.
final class PrefCheckbox: NSButton {
    private let key: String

    init(title: String, key: String) {
        self.key = key
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() { UserDefaults.standard.set(state == .on, forKey: key) }
}
