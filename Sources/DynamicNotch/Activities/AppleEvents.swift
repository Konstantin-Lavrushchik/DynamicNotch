import Foundation
import Carbon.HIToolbox

/// Raw Apple Events for the Music app: the same messages AppleScript sends, without loading the
/// AppleScript engine and Music's scripting dictionary (that cost ~13 MB of memory).
/// Codes come from Music's scripting definition (same as iTunes).
enum MusicEvents {
    private static let bundleID = "com.apple.Music"
    private static let queue = DispatchQueue(label: "dynamicnotch.musicevents", qos: .userInitiated)

    static func code(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

    /// `property <code> of <container>` (container nil = the application).
    static func property(_ prop: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: DescType(typeObjectSpecifier))!
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: DescType(typeProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: code(prop)), forKeyword: AEKeyword(keyAEKeyData))
        spec.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
        return spec
    }

    /// `<class> <index> of <container>`, e.g. artwork 1 of current track.
    static func element(_ cls: String, index: Int32, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: DescType(typeObjectSpecifier))!
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: code(cls)), forKeyword: AEKeyword(keyAEDesiredClass))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formAbsolutePosition)), forKeyword: AEKeyword(keyAEKeyForm))
        spec.setDescriptor(NSAppleEventDescriptor(int32: index), forKeyword: AEKeyword(keyAEKeyData))
        spec.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return spec
    }

    static var currentTrack: NSAppleEventDescriptor { property("pTrk") }

    private static var permitted = false

    /// Asks macOS for Automation permission (shows the "control Music" prompt the first time)
    /// and waits for the answer. Runs on the events queue, never on main.
    private static func ensurePermission() -> Bool {
        if permitted { return true }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        permitted = status == noErr
        if !permitted { NSLog("DynamicNotch: Music automation not allowed (%d)", status) }
        return permitted
    }

    /// Sends one event and returns the reply's direct object (nil on any error).
    static func send(_ eventClass: String, _ eventID: String, direct: NSAppleEventDescriptor? = nil,
                     params: [(String, NSAppleEventDescriptor)] = []) -> NSAppleEventDescriptor? {
        guard ensurePermission() else { return nil }
        let event = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID),
                                           targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        if let direct { event.setParam(direct, forKeyword: AEKeyword(keyDirectObject)) }
        for (key, value) in params { event.setParam(value, forKeyword: code(key)) }
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 3)
        } catch {
            NSLog("DynamicNotch AE %@/%@ failed: %@", eventClass, eventID, String(describing: error))
            return nil
        }
        if let err = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)) {
            NSLog("DynamicNotch AE %@/%@ error %d", eventClass, eventID, err.int32Value)
            return nil
        }
        return reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
    }

    static func get(_ spec: NSAppleEventDescriptor) -> NSAppleEventDescriptor? { send("core", "getd", direct: spec) }

    /// Runs `work` off the main thread and hands the result back on main.
    static func run<T>(_ work: @escaping () -> T, then done: @escaping @MainActor (T) -> Void) {
        queue.async {
            let box = UncheckedBox(work())
            DispatchQueue.main.async { MainActor.assumeIsolated { done(box.value) } }
        }
    }

    // MARK: Music app helpers

    struct NowPlaying { var playing: Bool; var name: String; var artist: String; var duration: Double; var position: Double }

    static func nowPlaying() -> NowPlaying? {
        guard let state = get(property("pPlS"))?.enumCodeValue else { return nil }
        if state == code("kPSS") { return nil }   // stopped
        let track = currentTrack
        return NowPlaying(playing: state == code("kPSP"),
                          name: get(property("pnam", of: track))?.stringValue ?? "",
                          artist: get(property("pArt", of: track))?.stringValue ?? "",
                          duration: get(property("pDur", of: track))?.doubleValue ?? 0,
                          position: get(property("pPos"))?.doubleValue ?? 0)
    }

    static func position() -> Double? { get(property("pPos"))?.doubleValue }

    static func artworkData() -> Data? {
        get(property("pRaw", of: element("cArt", index: 1, of: currentTrack)))?.data
    }

    static func playPause() { _ = send("hook", "PlPs") }
    static func nextTrack() { _ = send("hook", "Next") }
    static func previousTrack() { _ = send("hook", "Prev") }

    static func setPosition(_ seconds: Double) {
        _ = send("core", "setd", direct: property("pPos"), params: [("data", NSAppleEventDescriptor(double: seconds))])
    }
}
