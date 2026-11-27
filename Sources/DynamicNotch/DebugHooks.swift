import Foundation

/// Test hook, only active when started with DYNAMICNOTCH_DEBUG=1:
///   open --env DYNAMICNOTCH_DEBUG=1 ~/Applications/DynamicNotch.app
///   then post the distributed notification "app.dynamicnotch.debug" with a command string
///   as its object, e.g. "timer:90", "stopwatch", "expand", "collapse", "alert:charging".
@MainActor
enum DebugHooks {
    static func installIfEnabled() {
        guard ProcessInfo.processInfo.environment["DYNAMICNOTCH_DEBUG"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.dynamicnotch.debug"),
                                                            object: nil, queue: .main) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { run(command) }
        }
    }

    static func run(_ command: String) {
        NSLog("DynamicNotch debug: %@", command)
        let model = IslandModel.shared
        let parts = command.split(separator: ":").map(String.init)
        switch parts.first ?? "" {
        case "timer": TimerProvider.shared.start(seconds: Double(parts.dropFirst().first ?? "60") ?? 60)
        case "canceltimer": TimerProvider.shared.cancel()
        case "stopwatch": StopwatchProvider.shared.toggle()
        case "resetstopwatch": StopwatchProvider.shared.reset()
        case "record": RecorderProvider.shared.toggle()
        case "expand": model.expand()
        case "collapse": model.collapse()
        case "swipe-up": model.swipe(.up)
        case "swipe-side": model.swipe(.sideways)
        case "switch": model.switchToSecondary()
        case "dropzone": model.setDropZone(parts.dropFirst().first == "on")
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
