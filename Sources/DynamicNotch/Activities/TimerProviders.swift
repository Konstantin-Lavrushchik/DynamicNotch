import AppKit
import SwiftUI

/// Countdown timer like the iPhone Clock timer: pause / cancel from the island, and an alarm
/// that opens the island and rings until you press Stop (or Repeat).
@MainActor
final class TimerProvider: ObservableObject {
    static let shared = TimerProvider()

    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var ringing = false
    private var fireTask: Task<Void, Never>?
    private var ringTask: Task<Void, Never>?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date) -> Double {
        total > 0 ? remaining(at: date) / total : 0
    }

    func start(seconds: TimeInterval) {
        stopAlarm()
        total = seconds
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(seconds)
        schedule()
        IslandModel.shared.setActive(.timer, true)
    }

    func togglePause() {
        if let left = pausedRemaining {
            pausedRemaining = nil
            endDate = Date().addingTimeInterval(left)
            schedule()
        } else if endDate != nil {
            pausedRemaining = remaining(at: Date())
            endDate = nil
            fireTask?.cancel()
        }
    }

    func cancel() {
        fireTask?.cancel()
        endDate = nil
        pausedRemaining = nil
        IslandModel.shared.setActive(.timer, false)
    }

    private func schedule() {
        fireTask?.cancel()
        guard let endDate else { return }
        fireTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, endDate.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    private func fire() {
        endDate = nil
        pausedRemaining = nil
        IslandModel.shared.setActive(.timer, false)
        ringing = true
        IslandModel.shared.setActive(.timerDone, true)
        IslandModel.shared.expand(alerting: true)
        ringTask = Task { @MainActor in
            // Ring for up to a minute, like an alarm.
            for _ in 0..<40 {
                NSSound(named: "Glass")?.play()
                try? await Task.sleep(for: .seconds(1.5))
                if Task.isCancelled { return }
            }
        }
    }

    func stopAlarm() {
        ringTask?.cancel()
        guard ringing else { return }
        ringing = false
        IslandModel.shared.setActive(.timerDone, false)
    }

    func repeatTimer() {
        let seconds = total
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
