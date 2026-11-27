import SwiftUI

/// What each Live Activity shows in its four presentations, the same split ActivityKit uses on
/// iPhone: compact leading / compact trailing / minimal / expanded.
@MainActor
enum ActivityViews {
    static func expandedHeight(_ id: ActivityID) -> CGFloat {
        switch id {
        case .music: 128
        case .download: 74
        case .timer: 68 + 48 * CGFloat(max(0, min(TimerProvider.shared.timers.count, TimerProvider.maxShown) - 1))
        default: 68
        }
    }

    static func leading(_ id: ActivityID) -> AnyView {
        switch id {
        case .music: AnyView(MusicArtwork(size: 22, corner: 6))
        case .alarm: AnyView(Image(systemName: "alarm.fill").font(.system(size: 14)).foregroundStyle(.orange).symbolEffect(.bounce, options: .repeating))
        case .snooze: AnyView(Image(systemName: "alarm").font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange))
        case .timer: AnyView(Image(systemName: "timer").font(.system(size: 15, weight: .semibold)).foregroundStyle(.orange))
        case .timerDone: AnyView(Image(systemName: "bell.fill").font(.system(size: 14)).foregroundStyle(.orange).symbolEffect(.bounce, options: .repeating))
        case .stopwatch: AnyView(Image(systemName: "stopwatch").font(.system(size: 15, weight: .semibold)).foregroundStyle(.orange))
        case .recording: AnyView(RecordingWave(bars: 6, height: 14))
        case .download: AnyView(Image(systemName: "arrow.down.circle.fill").font(.system(size: 17)).foregroundStyle(.blue))
        }
    }

    static func trailing(_ id: ActivityID) -> AnyView {
        switch id {
        case .music: AnyView(MusicWaveform(height: 14))
        case .alarm: AnyView(AlarmTime(size: 13))
        case .snooze: AnyView(SnoozeText(size: 13))
        case .timer: AnyView(TimerText(size: 13))
        case .timerDone: AnyView(Text("Done").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange))
        case .stopwatch: AnyView(StopwatchText(size: 13, precise: false))
        case .recording: AnyView(RecordingTime(size: 13))
        case .download: AnyView(DownloadRing(size: 18))
        }
    }

    static func minimal(_ id: ActivityID) -> AnyView {
        switch id {
        case .music: AnyView(MusicArtwork(size: 18, corner: 9))
        case .alarm: AnyView(Image(systemName: "alarm.fill").font(.system(size: 12)).foregroundStyle(.orange))
        case .snooze: AnyView(Image(systemName: "alarm").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange))
        case .timer: AnyView(TimerRing(size: 18))
        case .timerDone: AnyView(Image(systemName: "bell.fill").font(.system(size: 12)).foregroundStyle(.orange))
        case .stopwatch: AnyView(Image(systemName: "stopwatch").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange))
        case .recording: AnyView(Circle().fill(Color.red).frame(width: 9, height: 9).symbolEffect(.pulse))
        case .download: AnyView(DownloadRing(size: 18))
        }
    }

    static func expanded(_ id: ActivityID) -> AnyView {
        switch id {
        case .music: AnyView(MusicExpanded())
        case .alarm: AnyView(AlarmExpanded())
        case .snooze: AnyView(SnoozeExpanded())
        case .timer: AnyView(TimerExpanded())
        case .timerDone: AnyView(TimerDoneExpanded())
        case .stopwatch: AnyView(StopwatchExpanded())
        case .recording: AnyView(RecordingExpanded())
        case .download: AnyView(DownloadExpanded())
        }
    }
}

@MainActor
enum ActivityActions {
    /// A click on the island opens the app behind the activity, like a tap on iPhone.
    static func open(_ id: ActivityID) {
        switch id {
        case .music: MusicProvider.shared.openApp()
        case .download: DownloadsMonitor.shared.openFolder()
        case .recording, .timer, .stopwatch, .snooze: IslandModel.shared.expand()
        case .timerDone, .alarm: break
        }
    }
}

// MARK: - Shared pieces

struct CircleButton: View {
    let symbol: String
    var tint: Color = .white
    var background: Color = Color.white.opacity(0.16)
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.islandSoft, value: configuration.isPressed)
    }
}

// MARK: - Music

struct MusicArtwork: View {
    @ObservedObject private var music = MusicProvider.shared
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let art = music.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .scaleEffect(music.isPlaying ? 1 : 0.9)
        .animation(.island, value: music.isPlaying)
    }
}

/// The dancing bars on the right of the island, tinted with the album colour.
struct MusicWaveform: View {
    @ObservedObject private var music = MusicProvider.shared
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !music.isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let phase = t * (5.2 + Double(i) * 1.3) + Double(i) * 1.7
                    let level = music.isPlaying ? 0.35 + 0.65 * abs(sin(phase) * cos(phase * 0.37)) : 0.18
                    Capsule().fill(music.tint)
                        .frame(width: 2.6, height: max(3, height * level))
                }
            }
            .frame(height: height)
        }
    }
}

struct MusicExpanded: View {
    @ObservedObject private var music = MusicProvider.shared
    @StateObject private var scrub = Box<Double?>(nil)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                MusicArtwork(size: 50, corner: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.title.isEmpty ? "Not Playing" : music.title)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(music.artist)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                MusicWaveform(height: 20)
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let pos = scrub.v ?? music.position(at: context.date)
                HStack(spacing: 8) {
                    Text(TimeFormat.elapsed(pos)).frame(width: 38, alignment: .leading)
                    GeometryReader { g in
                        let fraction = music.duration > 0 ? pos / music.duration : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(Color.white).frame(width: g.size.width * fraction)
                        }
                        .frame(height: scrub.v == nil ? 5 : 8)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in scrub.v = max(0, min(1, v.location.x / g.size.width)) * music.duration }
                            .onEnded { _ in
                                if let s = scrub.v { music.seek(to: s) }
                                scrub.v = nil
                            })
                    }
                    .frame(height: 12)
                    Text("-" + TimeFormat.elapsed(max(0, music.duration - pos))).frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .animation(.islandSoft, value: scrub.v == nil)
            }

            HStack(spacing: 34) {
                Button { music.previous() } label: { Image(systemName: "backward.fill") }
                Button { music.togglePlay() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 30)
                }
                Button { music.next() } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(PressScale())
            .font(.system(size: 20))
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Timer

struct TimerText: View {
    @ObservedObject private var timers = TimerProvider.shared
    var id: UUID? = nil   // nil = the timer ending soonest
    let size: CGFloat

    var body: some View {
        let timer = id.flatMap { id in timers.timers.first { $0.id == id } } ?? timers.current
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            Text(TimeFormat.clock(timer?.remaining(at: context.date) ?? 0))
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .contentTransition(.numericText(countsDown: true))
                .opacity(timer?.isPaused == true ? 0.55 : 1)
        }
    }
}

struct TimerRing: View {
    @ObservedObject private var timers = TimerProvider.shared
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            ZStack {
                Circle().stroke(Color.orange.opacity(0.3), lineWidth: 2.5)
                Circle().trim(from: 0, to: timers.current?.progress(at: context.date) ?? 0)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
        }
    }
}

/// One row per timer (up to three), like the iPhone timers Live Activity.
struct TimerExpanded: View {
    @ObservedObject private var timers = TimerProvider.shared

    var body: some View {
        let list = Array(timers.ordered.prefix(TimerProvider.maxShown))
        VStack(spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, timer in
                let first = index == 0
                HStack(spacing: 10) {
                    CircleButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", tint: .orange,
                                 background: Color.orange.opacity(0.25), size: first ? 40 : 34) { timers.togglePause(timer.id) }
                    CircleButton(symbol: "xmark", size: first ? 40 : 34) { timers.cancel(timer.id) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timer.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                        TimerText(id: timer.id, size: first ? 34 : 24)
                    }
                }
            }
            if timers.timers.count > list.count {
                Text("+\(timers.timers.count - list.count) more").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

struct TimerDoneExpanded: View {
    @ObservedObject private var timer = TimerProvider.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.orange.opacity(0.22)))
                .symbolEffect(.bounce, options: .repeating)
            VStack(alignment: .leading, spacing: 0) {
                Text(timer.ringing?.label ?? "Timer").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Text("Done").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            }
            Spacer()
            CircleButton(symbol: "arrow.counterclockwise") { timer.repeatTimer() }
            Button { timer.stopAlarm() } label: {
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 76, height: 40)
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(PressScale())
        }
    }
}

// MARK: - Stopwatch

struct StopwatchText: View {
    @ObservedObject private var stopwatch = StopwatchProvider.shared
    let size: CGFloat
    let precise: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: precise ? 0.03 : 0.25)) { context in
            let t = stopwatch.elapsed(at: context.date)
            Text(precise ? TimeFormat.stopwatch(t) : TimeFormat.elapsed(t))
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .opacity(stopwatch.isRunning ? 1 : 0.55)
        }
    }
}

struct StopwatchExpanded: View {
    @ObservedObject private var stopwatch = StopwatchProvider.shared

    var body: some View {
        HStack(spacing: 10) {
            CircleButton(symbol: stopwatch.isRunning ? "pause.fill" : "play.fill", tint: .orange,
                         background: Color.orange.opacity(0.25)) { stopwatch.toggle() }
            if stopwatch.isRunning {
                CircleButton(symbol: "flag.fill") { stopwatch.lap() }
            } else {
                CircleButton(symbol: "arrow.counterclockwise") { stopwatch.reset() }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(stopwatch.laps.isEmpty ? "Stopwatch" : "Lap \(stopwatch.laps.count + 1)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                StopwatchText(size: 30, precise: true)
            }
        }
    }
}

// MARK: - Voice memo

struct RecordingWave: View {
    @ObservedObject private var recorder = RecorderProvider.shared
    let bars: Int
    let height: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(recorder.levels.suffix(bars).enumerated()), id: \.offset) { _, level in
                Capsule().fill(Color.red).frame(width: 2.4, height: max(3, height * level))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.06), value: recorder.levels)
    }
}

struct RecordingTime: View {
    @ObservedObject private var recorder = RecorderProvider.shared
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(TimeFormat.elapsed(recorder.elapsed(at: context.date)))
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(.red)
        }
    }
}

struct RecordingExpanded: View {
    @ObservedObject private var recorder = RecorderProvider.shared

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                RecordingTime(size: 26)
            }
            RecordingWave(bars: 24, height: 30).frame(maxWidth: .infinity)
            Button { recorder.stop() } label: {
                RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 16, height: 16)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(PressScale())
        }
    }
}

// MARK: - Downloads

struct DownloadRing: View {
    @ObservedObject private var downloads = DownloadsMonitor.shared
    let size: CGFloat
    @StateObject private var spinning = Box(false)

    var body: some View {
        ZStack {
            Circle().stroke(Color.blue.opacity(0.3), lineWidth: 2.5)
            if let f = downloads.overallFraction {
                Circle().trim(from: 0, to: f)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.islandSoft, value: f)
            } else {
                Circle().trim(from: 0, to: 0.28)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spinning.v ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning.v)
                    .onAppear { spinning.v = true }
            }
        }
        .frame(width: size, height: size)
    }
}

struct DownloadExpanded: View {
    @ObservedObject private var downloads = DownloadsMonitor.shared

    var body: some View {
        let first = downloads.items.first
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 30)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(downloads.items.count > 1 ? "\(downloads.items.count) downloads" : (first?.name ?? "Downloading"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                if let f = downloads.overallFraction {
                    ProgressView(value: f).tint(.blue)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(.blue)
                }
                Text(sizeText(first)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
            }
            CircleButton(symbol: "folder.fill", size: 36) { downloads.openFolder() }
        }
    }

    private func sizeText(_ item: DownloadItem?) -> String {
        guard let item else { return "" }
        let f = ByteCountFormatter()
        if let total = item.total { return "\(f.string(fromByteCount: item.bytes)) of \(f.string(fromByteCount: total))" }
        return f.string(fromByteCount: item.bytes)
    }
}

// MARK: - Alarm

struct AlarmTime: View {
    @ObservedObject private var alarms = AlarmProvider.shared
    let size: CGFloat
    var body: some View {
        Text(alarms.ringing?.timeText ?? "")
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .foregroundStyle(.orange)
    }
}

struct AlarmExpanded: View {
    @ObservedObject private var alarms = AlarmProvider.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.orange.opacity(0.22)))
                .symbolEffect(.bounce, options: .repeating)
            VStack(alignment: .leading, spacing: 0) {
                Text("Alarm").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Text(alarms.ringing?.timeText ?? "").font(.system(size: 22, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            }
            Spacer()
            Button { alarms.snooze() } label: {
                Text("Snooze")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 40)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(PressScale())
            Button { alarms.stop() } label: {
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 76, height: 40)
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(PressScale())
        }
    }
}

struct SnoozeText: View {
    @ObservedObject private var alarms = AlarmProvider.shared
    let size: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(TimeFormat.clock(alarms.snoozeRemaining(at: context.date)))
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .contentTransition(.numericText(countsDown: true))
        }
    }
}

struct SnoozeExpanded: View {
    @ObservedObject private var alarms = AlarmProvider.shared

    var body: some View {
        HStack(spacing: 10) {
            Button { alarms.stop() } label: {
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 40)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(PressScale())
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("Snooze").font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                SnoozeText(size: 34)
            }
        }
    }
}
