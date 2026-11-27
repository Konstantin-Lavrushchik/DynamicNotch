import AppKit

/// Test hook, only active when started with DYNAMICNOTCH_DEBUG=1:
///   open --env DYNAMICNOTCH_DEBUG=1 ~/Applications/DynamicNotch.app
///   then post the distributed notification "app.dynamicnotch.debug" with a command string
///   as its object, e.g. "timer:90", "stopwatch", "expand", "collapse", "alert:charging".
@MainActor
enum DebugHooks {
    static func installIfEnabled() {
        guard ProcessInfo.processInfo.environment["DYNAMICNOTCH_DEBUG"] == "1" else { return }
        SystemNotifications.observe("app.dynamicnotch.debug") { note in
            run(note.object as? String ?? "")
        }
    }

    static func run(_ command: String) {
        NSLog("DynamicNotch debug: %@", command)
        let model = IslandModel.shared
        let parts = command.split(separator: ":").map(String.init)
        switch parts.first ?? "" {
        case "timer": TimerProvider.shared.start(seconds: Double(parts.dropFirst().first ?? "60") ?? 60)
        case "canceltimer": TimerProvider.shared.cancelAll()
        case "alarm": AlarmProvider.shared.add(date: Date().addingTimeInterval(Double(parts.dropFirst().first ?? "5") ?? 5))
        case "snooze": AlarmProvider.shared.snooze()
        case "stopalarm": AlarmProvider.shared.stop()
        case "stoptimer": TimerProvider.shared.stopAlarm()
        case "stopwatch": StopwatchProvider.shared.toggle()
        case "resetstopwatch": StopwatchProvider.shared.reset()
        case "record": RecorderProvider.shared.toggle()
        case "expand": model.expand()
        case "settings": (NSApp.delegate as? AppDelegate)?.openSettings()
        case "pref": if parts.count == 3 { UserDefaults.standard.set(parts[2] == "1", forKey: parts[1]) }
        case "state":
            NSLog("DynamicNotch music: source=%@ title=%@ artist=%@ playing=%d artwork=%d dur=%.0f pos=%.0f", String(describing: MusicProvider.shared.source), MusicProvider.shared.title, MusicProvider.shared.artist, MusicProvider.shared.isPlaying ? 1 : 0, MusicProvider.shared.artwork == nil ? 0 : 1, MusicProvider.shared.duration, MusicProvider.shared.position(at: Date()))
            NSLog("DynamicNotch state: alert=%@ active=%@ primary=%@ expanded=%d hidden=%d size=%@ mic=%d cam=%d", String(describing: model.alert?.kind), String(describing: model.active.sorted().map { "\($0)" }), String(describing: model.primary), model.expanded ? 1 : 0, model.hidden ? 1 : 0, NSStringFromSize(model.size), model.micInUse ? 1 : 0, model.cameraInUse ? 1 : 0)
        case "music":
            switch parts.dropFirst().first ?? "" {
            case "toggle": MusicProvider.shared.togglePlay()
            case "next": MusicProvider.shared.next()
            case "prev": MusicProvider.shared.previous()
            case "seek": MusicProvider.shared.seek(to: Double(parts.dropFirst(2).first ?? "0") ?? 0)
            default: break
            }
        case "closesettings": NSApp.windows.first { $0.title.contains("Settings") }?.performClose(nil)
        case "collapse": model.collapse()
        case "swipe-up": model.swipe(.up)
        case "swipe-side": model.swipe(.sideways)
        case "switch": model.switchToSecondary()
        case "alert":
            switch parts.dropFirst().first ?? "" {
            case "charging": model.show(.charging(percent: 64), for: 4)
            case "low": model.show(.lowBattery(percent: 20), for: 4)
            case "silent": model.show(.silent(on: true), for: 4)
            case "ring": model.show(.silent(on: false), for: 4)
            case "volume": model.show(.volume(level: 0.6), for: 4)
            case "airpods": model.show(.headphones(name: "AirPods Pro", symbol: "airpodspro",
                                                   batteries: [.init(label: "L", percent: 90), .init(label: "R", percent: 85), .init(label: "C", percent: 40)]), for: 4)
            case "unlock": model.show(.unlocked, for: 3)
            case "downloaded": model.show(.downloaded(name: "Report.pdf"), for: 4)
            default: break
            }
        default: break
        }
    }
}
