import AppKit
import AVFoundation

/// Voice memo recording from the island (the iPhone Voice Memos Live Activity).
/// Files go to ~/Documents/Dynamic Notch Recordings as .m4a.
@MainActor
final class RecorderProvider: ObservableObject {
    static let shared = RecorderProvider()

    @Published private(set) var isRecording = false
    @Published private(set) var startDate: Date?
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.05, count: 32)
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

    var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dynamic Notch Recordings", isDirectory: true)
    }

    func toggle() { isRecording ? stop() : start() }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { MainActor.assumeIsolated { if ok { RecorderProvider.shared.begin() } } }
            }
        default:
            let alert = NSAlert()
            alert.messageText = "Microphone access is off"
            alert.informativeText = "Turn on Dynamic Notch in System Settings → Privacy & Security → Microphone."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func begin() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = folder.appendingPathComponent("Recording \(formatter.string(from: Date())).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.isMeteringEnabled = true
        guard rec.record() else { return }
        recorder = rec
        startDate = Date()
        isRecording = true
        IslandModel.shared.setActive(.recording, true)
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            MainActor.assumeIsolated { RecorderProvider.shared.sampleLevel() }
        }
    }

    private func sampleLevel() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)   // -160 … 0
        let level = CGFloat(max(0.05, min(1, (db + 50) / 50)))
        levels.removeFirst()
        levels.append(level)
    }

    func stop() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        startDate = nil
        levels = Array(repeating: 0.05, count: levels.count)
        IslandModel.shared.setActive(.recording, false)
    }

    func elapsed(at date: Date) -> TimeInterval { startDate.map { date.timeIntervalSince($0) } ?? 0 }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
