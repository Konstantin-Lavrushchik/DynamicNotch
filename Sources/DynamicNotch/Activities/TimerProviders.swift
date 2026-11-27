import AppKit
import SwiftUI

/// One countdown. Running timers have an end date; paused ones keep what was left.
struct CountdownTimer: Identifiable, Equatable {
    let id = UUID()
    var total: TimeInterval
    var endDate: Date?
    var pausedRemaining: TimeInterval?

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, (endDate ?? date).timeIntervalSince(date))
    }

    func progress(at date: Date) -> Double { total > 0 ? remaining(at: date) / total : 0 }

    /// "5 min", "1 hr 30 min", "45 sec" — how iPhone names timers.
    var label: String {
        let s = Int(total.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if sec > 0 && h == 0 { parts.append("\(sec) sec") }
        return parts.isEmpty ? "Timer" : parts.joined(separator: " ")
    }
}

/// Countdown timers like the iPhone Clock app (iOS 17+): several can run at once. The island
/// shows the one ending soonest; the expanded view lists them all. A finished timer opens the
/// island and rings until Stop (or Repeat).
@MainActor
final class TimerProvider: ObservableObject {
    static let shared = TimerProvider()
    static let maxShown = 3

    @Published private(set) var timers: [CountdownTimer] = []
    @Published private(set) var ringing: CountdownTimer?
    private var fireTask: Task<Void, Never>?
    private var ringTask: Task<Void, Never>?

    var isActive: Bool { !timers.isEmpty }

    /// Running timers first (soonest end first), then paused ones.
    var ordered: [CountdownTimer] {
        let now = Date()
        return timers.sorted { a, b in
            if a.isPaused != b.isPaused { return !a.isPaused }
            return a.remaining(at: now) < b.remaining(at: now)
        }
    }

    var current: CountdownTimer? { ordered.first }

    func start(seconds: TimeInterval) {
        timers.append(CountdownTimer(total: seconds, endDate: Date().addingTimeInterval(seconds)))
        changed()
    }

    func togglePause(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        if let left = timers[i].pausedRemaining {
            timers[i].pausedRemaining = nil
            timers[i].endDate = Date().addingTimeInterval(left)
        } else {
            timers[i].pausedRemaining = timers[i].remaining(at: Date())
            timers[i].endDate = nil
        }
        changed()
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        changed()
    }

    func cancelAll() {
        timers.removeAll()
        changed()
    }

    private func changed() {
        IslandModel.shared.setActive(.timer, !timers.isEmpty)
        scheduleNext()
    }

    /// One sleeping task for whichever running timer ends next.
    private func scheduleNext() {
        fireTask?.cancel()
        guard let next = timers.compactMap(\.endDate).min() else { return }
        fireTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.fireDue()
        }
    }

    private func fireDue() {
        let now = Date()
        let due = timers.filter { ($0.endDate ?? .distantFuture) <= now.addingTimeInterval(0.05) }
        timers.removeAll { t in due.contains { $0.id == t.id } }
        changed()
        if let first = due.first { ring(first) }
    }

    private func ring(_ timer: CountdownTimer) {
        ringing = timer
        IslandModel.shared.setActive(.timerDone, true)
        IslandModel.shared.expand(alerting: true)
        ringTask?.cancel()
        ringTask = Task { @MainActor in
            for _ in 0..<40 {   // about a minute, like an alarm
                NSSound(named: "Glass")?.play()
                try? await Task.sleep(for: .seconds(1.5))
                if Task.isCancelled { return }
            }
        }
    }

    func stopAlarm() {
        ringTask?.cancel()
        guard ringing != nil else { return }
        ringing = nil
        IslandModel.shared.setActive(.timerDone, false)
    }

    func repeatTimer() {
        guard let seconds = ringing?.total else { return }
        stopAlarm()
        start(seconds: seconds)
    }
}

@MainActor
final class StopwatchProvider: ObservableObject {
    static let shared = StopwatchProvider()

    @Published private(set) var startDate: Date?
    @Published private(set) var accumulated: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []

    var isRunning: Bool { startDate != nil }
    var isActive: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startDate.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle() {
        if let startDate {
            accumulated += Date().timeIntervalSince(startDate)
            self.startDate = nil
        } else {
            startDate = Date()
        }
        IslandModel.shared.setActive(.stopwatch, isActive)
    }

    func lap() {
        guard isRunning else { return }
        laps.append(elapsed(at: Date()))
    }

    func reset() {
        startDate = nil
        accumulated = 0
        laps = []
        IslandModel.shared.setActive(.stopwatch, false)
    }
}

enum TimeFormat {
    /// 4:05, 12:00, 1:02:03
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Elapsed time, rounding down (stopwatch, recording, song position).
    static func elapsed(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 00:12,34 like the iPhone stopwatch.
    static func stopwatch(_ t: TimeInterval) -> String {
        let cs = Int(max(0, t) * 100)
        let m = cs / 6000, s = (cs / 100) % 60, c = cs % 100
        return String(format: "%02d:%02d,%02d", m, s, c)
    }
}
