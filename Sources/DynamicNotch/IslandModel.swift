import AppKit
import SwiftUI

/// Ongoing Live Activities. Earlier cases win when several run at once (system activities
/// first, like on iPhone).
enum ActivityID: Int, CaseIterable, Comparable {
    case alarm, timerDone, recording, snooze, timer, stopwatch, music, download

    static func < (a: ActivityID, b: ActivityID) -> Bool { a.rawValue < b.rawValue }
}

enum Swipe { case up, down, sideways }

extension Animation {
    /// The island's springy "blob" motion.
    static let island = Animation.spring(response: 0.42, dampingFraction: 0.74)
    static let islandSoft = Animation.spring(response: 0.36, dampingFraction: 0.9)
}

/// Short system alerts (charging, AirPods, silent mode, unlock, …). They take over the island
/// for a few seconds and then give it back to the Live Activities.
struct IslandAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case charging(percent: Int)
        case lowBattery(percent: Int)
        case silent(on: Bool)
        case volume(level: Float)
        case headphones(name: String, symbol: String, batteries: [HeadphoneBattery])
        case unlocked
        case downloaded(name: String)

        var category: Int {
            switch self {
            case .charging: 0
            case .lowBattery: 1
            case .silent: 2
            case .volume: 3
            case .headphones: 4
            case .unlocked: 5
            case .downloaded: 6
            }
        }
    }

    let id = UUID()
    var kind: Kind

    /// Width of each "ear" next to the notch.
    var earWidth: CGFloat {
        switch kind {
        case .unlocked: 34
        case .volume: 110
        case .headphones: 104
        case .lowBattery: 110
        case .downloaded: 120
        default: 96
        }
    }
}

struct HeadphoneBattery: Equatable, Hashable {
    var label: String   // "L", "R", "Case" or ""
    var percent: Int
}

@MainActor
final class IslandModel: ObservableObject {
    static let shared = IslandModel()

    @Published var notch = NotchGeometry.current()
    @Published private(set) var expanded = false
    @Published private(set) var hidden = false
    @Published private(set) var alert: IslandAlert?
    @Published private(set) var active: Set<ActivityID> = []
    @Published private(set) var pinned: ActivityID?
    @Published var micInUse = false
    @Published var cameraInUse = false
    @Published var mouseInside = false
    /// Set while an expanded view must stay open even when the pointer leaves (timer alarm).
    var holdOpen: Bool { active.contains(.alarm) || active.contains(.timerDone) }

    private var alertTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?

    // MARK: Activities

    var primary: ActivityID? {
        if active.contains(.alarm) { return .alarm }
        if active.contains(.timerDone) { return .timerDone }
        if let pinned, active.contains(pinned) { return pinned }
        return active.sorted().first
    }

    var secondary: ActivityID? {
        let p = primary
        return active.sorted().first { $0 != p }
    }

    var privacyDot: Bool { (micInUse || cameraInUse) && Prefs.on(Prefs.showPrivacy) }

    var showBubble: Bool { !expanded && alert == nil && !hidden && secondary != nil }

    func setActive(_ id: ActivityID, _ on: Bool) {
        guard on != active.contains(id) else { return }
        withAnimation(.island) {
            if on { active.insert(id) } else { active.remove(id) }
            if pinned == id && !on { pinned = nil }
            if primary == nil { expanded = false }
            if active.isEmpty { hidden = false }
        }
    }

    /// Tap on the minimal bubble: swap the two activities.
    func switchToSecondary() {
        guard let s = secondary else { return }
        withAnimation(.island) { pinned = s }
    }

    // MARK: Expand / collapse

    func expand(alerting: Bool = false) {
        guard primary != nil, !expanded else { return }
        withAnimation(.island) {
            hidden = false
            expanded = true
        }
        if Prefs.on(Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        autoCollapseTask?.cancel()
        if alerting {
            // An alerting update opens the island by itself and closes it again a few seconds later.
            autoCollapseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, !self.mouseInside, !self.holdOpen else { return }
                self.collapse()
            }
        }
    }

    func collapse() {
        guard expanded, !holdOpen else { return }
        autoCollapseTask?.cancel()
        withAnimation(.island) { expanded = false }
    }

    func setHidden(_ value: Bool) {
        withAnimation(.island) {
            hidden = value && primary != nil
            if hidden { expanded = false }
        }
    }

    func swipe(_ swipe: Swipe) {
        switch swipe {
        case .up:
            collapse()
        case .down:
            if !expanded && !hidden { expand() }
        case .sideways:
            if expanded { collapse() }
            if hidden { setHidden(false) } else if primary != nil { setHidden(true) }
        }
    }

    /// Click on the island. Like a tap on iPhone it opens the app behind the activity.
    func tap() {
        guard let p = primary, !hidden else { return }
        if ActivityActions.hasApp(p) {
            ActivityActions.open(p)
            if expanded { collapse() }
        } else if expanded {
            collapse()
        } else {
            // Timer, stopwatch, voice memo… have no app on the Mac: a click opens the island.
            expand()
        }
    }

    // MARK: Alerts

    func show(_ kind: IslandAlert.Kind, for seconds: Double = 2.6) {
        if var current = alert, current.kind.category == kind.category {
            current.kind = kind  // same alert updating (e.g. volume) keeps its identity
            withAnimation(.islandSoft) { alert = current }
        } else {
            withAnimation(.island) { alert = IslandAlert(kind: kind) }
        }
        alertTask?.cancel()
        alertTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.island) { self?.alert = nil }
        }
    }

    // MARK: Geometry

    static let flare: CGFloat = 6
    static let compactEar: CGFloat = 38
    static let bubbleGap: CGFloat = 6

    var topRadius: CGFloat { isIdle ? 0 : Self.flare }

    var bottomRadius: CGFloat {
        if expanded && alert == nil { return 30 }
        return isIdle ? min(10, notch.size.height / 3) : notch.size.height / 2
    }

    var isIdle: Bool {
        alert == nil && (primary == nil || hidden) && !privacyDot
    }

    var size: CGSize {
        let n = notch.size
        if let alert { return CGSize(width: n.width + 2 * (alert.earWidth + Self.flare), height: n.height) }
        if expanded, let p = primary {
            return CGSize(width: max(n.width + 300, 480), height: n.height + ActivityViews.expandedHeight(p))
        }
        if isIdle { return n }
        var ear: CGFloat = (!hidden && primary != nil) ? Self.compactEar : 0
        if privacyDot { ear += ear == 0 ? 18 : 12 }
        return CGSize(width: n.width + 2 * (ear + Self.flare), height: n.height)
    }

    var bubbleDiameter: CGFloat { notch.size.height }

    /// The island (and the minimal bubble) in screen coordinates, for mouse pass-through.
    var hitRect: CGRect {
        let screen = notch.screenFrame
        let s = size
        var rect = CGRect(x: screen.midX - s.width / 2, y: screen.maxY - s.height, width: s.width, height: s.height)
        if showBubble {
            rect.size.width += Self.bubbleGap + bubbleDiameter
        }
        return rect
    }
}

/// Stand-in for @State: the Command Line Tools have no SwiftUI macro plugin, so @State can't
/// be expanded here. A tiny ObservableObject held by @StateObject does the same job.
final class Box<T>: ObservableObject {
    @Published var v: T
    init(_ v: T) { self.v = v }
}

/// Listens to system-wide notifications with "deliver immediately". The block-based API uses
/// the default suspension behaviour, so a background app (which this always is) got them
/// late or coalesced — unlock and song changes showed up late.
@MainActor
enum SystemNotifications {
    private final class Observer: NSObject {
        let handler: @MainActor (Notification) -> Void
        init(_ handler: @escaping @MainActor (Notification) -> Void) { self.handler = handler }
        @objc func fire(_ note: Notification) {
            let box = UncheckedBox(note)
            if Thread.isMainThread {
                MainActor.assumeIsolated { handler(box.value) }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.handler(box.value) } }
            }
        }
    }

    private static var observers: [Observer] = []

    static func observe(_ name: String, _ handler: @escaping @MainActor (Notification) -> Void) {
        let observer = Observer(handler)
        observers.append(observer)
        DistributedNotificationCenter.default().addObserver(observer, selector: #selector(Observer.fire(_:)),
                                                            name: Notification.Name(name), object: nil,
                                                            suspensionBehavior: .deliverImmediately)
    }
}
