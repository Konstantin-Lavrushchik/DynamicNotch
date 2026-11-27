import AppKit

struct Alarm: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date

    var timeText: String { date.formatted(date: .omitted, time: .shortened) }
}

/// Alarms like the iPhone Clock app: when one goes off the island opens with Snooze and Stop.
/// Snooze is 9 minutes (Apple's value) and shows as a countdown Live Activity.
/// Alarms are kept across restarts. A sleeping Mac rings as soon as it wakes.
@MainActor
final class AlarmProvider: ObservableObject {
    static let shared = AlarmProvider()
    static let snoozeMinutes: TimeInterval = 9
    private static let storeKey = "alarms"

    @Published private(set) var alarms: [Alarm] = []
    @Published private(set) var ringing: Alarm?
    @Published private(set) var snoozeEnd: Date?
    private var waitTask: Task<Void, Never>?
    private var ringTask: Task<Void, Never>?

    func start() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = saved
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AlarmProvider.shared.check() }
        }
        check()
    }

    /// Adds an alarm for the next time the clock shows hour:minute.
    func add(hour: Int, minute: Int) {
        let cal = Calendar.current
        var date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        if date <= Date() { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
        add(date: date)
    }

    func add(date: Date) {
        alarms.append(Alarm(date: date))
        alarms.sort { $0.date < $1.date }
        save()
        scheduleNext()
    }

    func remove(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        save()
        scheduleNext()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(alarms) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }

    private func scheduleNext() {
        waitTask?.cancel()
        let next = ([snoozeEnd].compactMap { $0 } + alarms.map(\.date)).min()
        guard let next else { return }
        waitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    private func check() {
        let now = Date().addingTimeInterval(0.05)
        if let end = snoozeEnd, end <= now, let alarm = ringingAfterSnooze {
            snoozeEnd = nil
            IslandModel.shared.setActive(.snooze, false)
            ring(alarm)
        } else if let due = alarms.first(where: { $0.date <= now }) {
            alarms.removeAll { $0.id == due.id }
            save()
            ring(due)
        }
        scheduleNext()
    }

    private var ringingAfterSnooze: Alarm?

    private func ring(_ alarm: Alarm) {
        ringing = alarm
        IslandModel.shared.setActive(.alarm, true)
        IslandModel.shared.expand(alerting: true)
        ringTask?.cancel()
        ringTask = Task { @MainActor in
            for _ in 0..<60 {   // rings for a few minutes, then gives up quietly
                NSSound(named: "Hero")?.play()
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
        }
    }

    func snooze() {
        guard let alarm = ringing else { return }
        silence()
        ringingAfterSnooze = alarm
        snoozeEnd = Date().addingTimeInterval(Self.snoozeMinutes * 60)
        IslandModel.shared.setActive(.snooze, true)
        scheduleNext()
    }

    func stop() {
        silence()
        snoozeEnd = nil
        ringingAfterSnooze = nil
        IslandModel.shared.setActive(.snooze, false)
        scheduleNext()
    }

    private func silence() {
        ringTask?.cancel()
        ringing = nil
        IslandModel.shared.setActive(.alarm, false)
    }

    func snoozeRemaining(at date: Date) -> TimeInterval { max(0, (snoozeEnd ?? date).timeIntervalSince(date)) }

    /// Asks for a time with a native clock picker.
    func askNewAlarm() {
        let alert = NSAlert()
        alert.messageText = "Add Alarm"
        alert.informativeText = "The island rings with Snooze and Stop at this time."
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 140, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = Date().addingTimeInterval(3600)
        picker.sizeToFit()
        alert.accessoryView = picker
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let c = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
            add(hour: c.hour ?? 7, minute: c.minute ?? 0)
        }
    }
}
