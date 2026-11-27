import AppKit
import SwiftUI
import CoreImage

/// Now Playing for Apple Music and Spotify. Both apps broadcast a distributed notification on
/// every play/pause/track change; artwork and position come from their AppleScript dictionaries.
/// The player apps are never launched by us: every script is guarded by "is it running".
@MainActor
final class MusicProvider: ObservableObject {
    static let shared = MusicProvider()

    enum Source: String {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"
        var scriptName: String { self == .music ? "Music" : "Spotify" }
    }

    @Published private(set) var source: Source?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var tint: Color = .white
    private var position: Double = 0
    private var positionDate = Date()
    private var trackKey = ""
    private var pausedTask: Task<Void, Never>?

    func position(at date: Date) -> Double {
        let p = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { MusicProvider.shared.handle(info, from: .music) }
        }
        center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { MusicProvider.shared.handle(info, from: .spotify) }
        }
        // Pick up a song that was already playing when we launched.
        for s in [Source.spotify, .music] where isRunning(s) { refresh(from: s) }
    }

    private func isRunning(_ s: Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: s.rawValue).isEmpty
    }

    private func handle(_ info: [AnyHashable: Any], from s: Source) {
        let state = (info["Player State"] as? String) ?? ""
        if state == "Stopped" || !isRunning(s) {
            if source == s { clear() }
            return
        }
        // Another player pausing must not take over the one that is playing.
        if let source, source != s, isPlaying, state != "Playing" { return }

        source = s
        isPlaying = state == "Playing"
        title = info["Name"] as? String ?? title
        artist = info["Artist"] as? String ?? ""
        if let ms = (info["Total Time"] ?? info["Duration"]) as? Double { duration = ms / 1000 }
        if let ms = (info["Total Time"] ?? info["Duration"]) as? Int { duration = Double(ms) / 1000 }
        if let pos = info["Playback Position"] as? Double { position = pos; positionDate = Date() }

        let key = "\(s.rawValue)|\(title)|\(artist)"
        if key != trackKey {
            trackKey = key
            artwork = nil
            tint = .white
            loadArtwork(from: s)
        }
        syncPosition()
        updateActivity()
    }

    private func refresh(from s: Source) {
        let script = """
        tell application "\(s.scriptName)"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as string, name of t, artist of t, duration of t, player position}
        end tell
        """
        AppleScript.run(script) { [weak self] result in
            guard let self, let r = result, r.numberOfItems >= 5 else { return }
            let state = r.atIndex(1)?.stringValue ?? ""
            var duration = r.atIndex(4)?.doubleValue ?? 0
            if s == .spotify { duration /= 1000 }
            self.handle([
                "Player State": state == "playing" ? "Playing" : "Paused",
                "Name": r.atIndex(2)?.stringValue ?? "",
                "Artist": r.atIndex(3)?.stringValue ?? "",
                "Total Time": duration * 1000,
                "Playback Position": r.atIndex(5)?.doubleValue ?? 0,
            ], from: s)
        }
    }

    private func syncPosition() {
        guard let s = source, isRunning(s) else { return }
        AppleScript.run("tell application \"\(s.scriptName)\" to get player position") { [weak self] r in
            guard let self, let p = r?.doubleValue else { return }
            self.position = p
            self.positionDate = Date()
            self.objectWillChange.send()
        }
    }

    private func loadArtwork(from s: Source) {
        let key = trackKey
        switch s {
        case .music:
            AppleScript.run("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] r in
                guard let self, key == self.trackKey, let data = r?.data, let image = NSImage(data: data) else { return }
                self.setArtwork(image)
            }
        case .spotify:
            AppleScript.run("tell application \"Spotify\" to get artwork url of current track") { [weak self] r in
                guard let url = r?.stringValue.flatMap(URL.init(string:)), url.scheme == "https" else { return }
                Task { @MainActor [weak self] in
                    guard let (data, _) = try? await URLSession.shared.data(from: url),
                          let image = NSImage(data: data), let self, key == self.trackKey else { return }
                    self.setArtwork(image)
                }
            }
        }
    }

    private func setArtwork(_ image: NSImage) {
        withAnimation(.islandSoft) {
            artwork = image
            tint = Self.averageColor(of: image)
        }
    }

    private func updateActivity() {
        pausedTask?.cancel()
        let on = Prefs.on(Prefs.showMusic) && source != nil
        IslandModel.shared.setActive(.music, on)
        if on && !isPlaying {
            // Like iPhone: a paused player stays in the island for a while, then leaves.
            pausedTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(180))
                guard !Task.isCancelled, let self, !self.isPlaying else { return }
                IslandModel.shared.setActive(.music, false)
            }
        }
    }

    private func clear() {
        source = nil
        isPlaying = false
        title = ""
        artist = ""
        artwork = nil
        trackKey = ""
        IslandModel.shared.setActive(.music, false)
    }

    // MARK: Controls

    func togglePlay() { command("playpause"); isPlaying.toggle(); position = position(at: Date()); positionDate = Date() }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        guard let s = source else { return }
        position = seconds
        positionDate = Date()
        objectWillChange.send()
        AppleScript.run("tell application \"\(s.scriptName)\" to set player position to \(seconds)")
    }

    func openApp() {
        guard let s = source, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func command(_ verb: String) {
        guard let s = source, isRunning(s) else { return }
        AppleScript.run("tell application \"\(s.scriptName)\" to \(verb)")
    }

    // MARK: Artwork colour (the waveform takes the album's colour, as on iPhone)

    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    static func averageColor(of image: NSImage) -> Color {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let output = filter.outputImage else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Keep it bright enough to read on black.
        return Color(hue: h, saturation: min(s * 1.2, 0.85), brightness: max(b, 0.82))
    }
}

/// Runs AppleScript on one serial background queue and hands the result back on main.
enum AppleScript {
    private static let queue = DispatchQueue(label: "dynamicnotch.applescript", qos: .userInitiated)

    static func run(_ source: String, completion: (@MainActor (NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let box = UncheckedBox(result)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion?(error == nil ? box.value : nil) }
            }
        }
    }
}

struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
