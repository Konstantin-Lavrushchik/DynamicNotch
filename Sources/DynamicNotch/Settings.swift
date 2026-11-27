import SwiftUI
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
        ])
    }

    static func on(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
}

struct SettingsView: View {
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = false
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.showMusic) private var showMusic = true
    @AppStorage(Prefs.showCharging) private var showCharging = true
    @AppStorage(Prefs.showHeadphones) private var showHeadphones = true
    @AppStorage(Prefs.showSilent) private var showSilent = true
    @AppStorage(Prefs.showVolume) private var showVolume = true
    @AppStorage(Prefs.showUnlock) private var showUnlock = true
    @AppStorage(Prefs.showDownloads) private var showDownloads = true
    @AppStorage(Prefs.showPrivacy) private var showPrivacy = true
    @StateObject private var login = Box(SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section("Island") {
                Toggle("Expand when the pointer rests on the island", isOn: $expandOnHover)
                Text("Off = iPhone behaviour: press and hold to expand, click to open the app, swipe up to collapse, swipe sideways to hide.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Trackpad haptic when the island expands", isOn: $haptics)
                Toggle("Open at login", isOn: $login.v)
                    .onChange(of: login.v) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            login.v = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("Live Activities") {
                Toggle("Now Playing (Music, Spotify)", isOn: $showMusic)
                Toggle("Downloads", isOn: $showDownloads)
                Toggle("Microphone and camera dots", isOn: $showPrivacy)
            }
            Section("Alerts") {
                Toggle("Charging and low battery", isOn: $showCharging)
                Toggle("AirPods and headphones", isOn: $showHeadphones)
                Toggle("Silent mode (sound muted)", isOn: $showSilent)
                Toggle("Volume", isOn: $showVolume)
                Toggle("Unlock", isOn: $showUnlock)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
    }
}
