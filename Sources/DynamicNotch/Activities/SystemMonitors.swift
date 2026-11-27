import AppKit
import SwiftUI
import IOKit.ps
import IOBluetooth
import CoreBluetooth
import CoreAudio
import AudioToolbox

func withAnimationIsland(_ body: () -> Void) { withAnimation(.island, body) }

// MARK: - Battery: "Charging 54%" when plugged in, "Low Battery" at 20% and 10%

@MainActor
final class BatteryMonitor {
    static let shared = BatteryMonitor()
    private var source: CFRunLoopSource?
    private var wasOnAC: Bool?
    private var lastPercent = 100

    func start() {
        let (ac, percent) = Self.read()
        wasOnAC = ac
        lastPercent = percent
        source = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { BatteryMonitor.shared.changed() } }
        }, nil)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func changed() {
        let (ac, percent) = Self.read()
        defer { wasOnAC = ac; lastPercent = percent }
        guard Prefs.on(Prefs.showCharging) else { return }
        if ac && wasOnAC == false {
            IslandModel.shared.show(.charging(percent: percent), for: 3)
        } else if !ac, percent < lastPercent, [20, 10, 5].contains(percent) {
            IslandModel.shared.show(.lowBattery(percent: percent), for: 4)
        }
    }

    static func read() -> (onAC: Bool, percent: Int) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (true, 100) }
        var ac = true, percent = 100
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            percent = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }
        return (ac, percent)
    }
}

// MARK: - AirPods / headphones connected

@MainActor
final class BluetoothMonitor: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothMonitor()
    private var connectNote: IOBluetoothUserNotification?
    private var central: CBCentralManager?
    private var startedAt = Date()

    /// IOBluetooth blocks the calling thread until Bluetooth permission is answered, which froze
    /// the whole app at launch. So ask through CoreBluetooth first (non-blocking prompt) and only
    /// register with IOBluetooth once access is allowed.
    func start() {
        switch CBManager.authorization {
        case .allowedAlways:
            register()
        case .notDetermined:
            central = CBCentralManager(delegate: self, queue: .main)
        default:
            break   // denied or restricted: no headphone alerts
        }
    }

    private func register() {
        guard connectNote == nil else { return }
        startedAt = Date()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if CBManager.authorization == .allowedAlways {
                self.central = nil
                self.register()
            }
        }
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Already-connected devices are reported at launch; don't pop alerts for those.
        guard Date().timeIntervalSince(startedAt) > 4, Prefs.on(Prefs.showHeadphones) else { return }
        let isAudio = device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio)
        let name = device.name ?? "Headphones"
        guard isAudio || name.localizedCaseInsensitiveContains("airpods") || name.localizedCaseInsensitiveContains("beats") else { return }
        let symbol = Self.symbol(for: name)
        IslandModel.shared.show(.headphones(name: name, symbol: symbol, batteries: []), for: 4)
        // Battery levels: macOS publishes them in System Information a moment after connecting.
        let address = device.addressString ?? ""
        Task.detached {
            try? await Task.sleep(for: .seconds(1.5))
            let levels = Self.batteryLevels(name: name, address: address)
            await MainActor.run {
                if !levels.isEmpty, case .headphones? = IslandModel.shared.alert?.kind {
                    IslandModel.shared.show(.headphones(name: name, symbol: symbol, batteries: levels), for: 3.5)
                }
            }
        }
    }

    nonisolated static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// Reads `system_profiler SPBluetoothDataType -json` (public CLI) for the device's battery.
    nonisolated static func batteryLevels(name: String, address: String) -> [HeadphoneBattery] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (devName, value) in entry {
                    guard let d = value as? [String: Any] else { continue }
                    let addr = (d["device_address"] as? String ?? "").replacingOccurrences(of: ":", with: "-").lowercased()
                    let wanted = address.replacingOccurrences(of: ":", with: "-").lowercased()
                    guard devName == name || (!wanted.isEmpty && addr == wanted) else { continue }
                    var out: [HeadphoneBattery] = []
                    for (key, label) in [("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"),
                                         ("device_batteryLevelCase", "C"), ("device_batteryLevelMain", "")] {
                        if let s = d[key] as? String, let v = Int(s.replacingOccurrences(of: "%", with: "")) {
                            out.append(HeadphoneBattery(label: label, percent: v))
                        }
                    }
                    return out
                }
            }
        }
        return []
    }
}

// MARK: - Output volume and mute (mute = iPhone silent mode)

@MainActor
final class AudioMonitor {
    static let shared = AudioMonitor()
    private var device: AudioDeviceID = 0
    private var listening: Set<AudioDeviceID> = []
    private var lastMuted: Bool?
    private var lastVolume: Float?
    private var quietUntil = Date().addingTimeInterval(2)

    func start() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            MainActor.assumeIsolated { AudioMonitor.shared.attach() }
        }
        attach()
    }

    private func attach() {
        device = Self.defaultOutput()
        lastMuted = Self.muted(device)
        lastVolume = Self.volume(device)
        quietUntil = Date().addingTimeInterval(0.5)  // switching devices is not a volume change
        guard device != 0, !listening.contains(device) else { return }
        listening.insert(device)
        let dev = device
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(dev, &addr, .main) { _, _ in
                MainActor.assumeIsolated { AudioMonitor.shared.changed(dev) }
            }
        }
    }

    private func changed(_ dev: AudioDeviceID) {
        guard dev == device, Date() > quietUntil else { return }
        let muted = Self.muted(dev)
        let volume = Self.volume(dev)
        defer { lastMuted = muted; lastVolume = volume }
        if let muted, muted != lastMuted {
            if Prefs.on(Prefs.showSilent) { IslandModel.shared.show(.silent(on: muted), for: 2) }
            return
        }
        if let volume, let lastVolume, abs(volume - lastVolume) > 0.001, Prefs.on(Prefs.showVolume) {
            IslandModel.shared.show(.volume(level: muted == true ? 0 : volume), for: 1.6)
        }
    }

    static func defaultOutput() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func volume(_ dev: AudioDeviceID) -> Float? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func muted(_ dev: AudioDeviceID) -> Bool? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }
}

// MARK: - Unlock animation

@MainActor
final class LockMonitor {
    static let shared = LockMonitor()

    func start() {
        SystemNotifications.observe("com.apple.screenIsUnlocked") { _ in
            guard Prefs.on(Prefs.showUnlock) else { return }
            // Wait until the desktop is visible again so the animation is actually seen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { IslandModel.shared.show(.unlocked, for: 1.6) }
            }
        }
    }
}

// MARK: - Downloads in progress (Safari, Chrome, Firefox, Edge…)

struct DownloadItem: Identifiable, Equatable {
    var id: String { tempName }
    let tempName: String
    var name: String
    var bytes: Int64
    var total: Int64?

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(bytes) / Double(total))
    }
}

@MainActor
final class DownloadsMonitor: ObservableObject {
    static let shared = DownloadsMonitor()
    @Published private(set) var items: [DownloadItem] = []
    private var timer: Timer?
    nonisolated private static let tempExtensions = ["download", "crdownload", "part", "opdownload", "partial"]

    var folder: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    var overallFraction: Double? {
        let known = items.compactMap { item in item.total.map { (item.bytes, $0) } }
        guard !known.isEmpty, known.count == items.count else { return nil }
        let done = known.reduce(Int64(0)) { $0 + $1.0 }, all = known.reduce(Int64(0)) { $0 + $1.1 }
        return all > 0 ? Double(done) / Double(all) : nil
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { DownloadsMonitor.shared.poll() }
        }
    }

    private var scanning = false
    private static let scanQueue = DispatchQueue(label: "dynamicnotch.downloads", qos: .utility)

    /// The folder is read on a background queue: the first read triggers macOS's Downloads
    /// permission prompt, which blocks the reading thread until answered.
    private func poll() {
        guard Prefs.on(Prefs.showDownloads) else {
            if !items.isEmpty { items = []; IslandModel.shared.setActive(.download, false) }
            return
        }
        guard !scanning else { return }
        scanning = true
        let folder = self.folder
        Self.scanQueue.async {
            let found = Self.scan(folder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DownloadsMonitor.shared.apply(found, folder: folder) }
            }
        }
    }

    private func apply(_ found: [DownloadItem]?, folder: URL) {
        scanning = false
        guard let found else { return }
        // Finished = temp file gone and the real file is there.
        for old in items where !found.contains(where: { $0.tempName == old.tempName }) {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(old.name).path) {
                IslandModel.shared.show(.downloaded(name: old.name), for: 3)
            }
        }
        if found != items { items = found }
        IslandModel.shared.setActive(.download, !found.isEmpty)
    }

    nonisolated private static func scan(_ folder: URL) -> [DownloadItem]? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return nil }
        var found: [DownloadItem] = []
        for temp in names {
            let ext = (temp as NSString).pathExtension.lowercased()
            guard tempExtensions.contains(ext) else { continue }
            let url = folder.appendingPathComponent(temp)
            var finalName = (temp as NSString).deletingPathExtension
            var bytes: Int64 = 0
            var total: Int64?
            if ext == "download" {
                // Safari keeps progress in the bundle's Info.plist.
                let plist = url.appendingPathComponent("Info.plist")
                if let dict = NSDictionary(contentsOf: plist) as? [String: Any] {
                    bytes = (dict["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    total = (dict["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
                    if let path = dict["DownloadEntryPath"] as? String { finalName = (path as NSString).lastPathComponent }
                }
            } else {
                bytes = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            }
            if finalName.hasPrefix("Unconfirmed ") || finalName.hasPrefix(".") { finalName = "File" }
            found.append(DownloadItem(tempName: temp, name: finalName, bytes: bytes, total: total))
        }
        return found
    }

    func openFolder() { NSWorkspace.shared.open(folder) }
}
