import SwiftUI
import UniformTypeIdentifiers

/// Flat top attached to the screen edge, small outward flares at the top corners (like the
/// MacBook notch) and round bottom corners. All three animate.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, rect.height, (rect.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandRootView: View {
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            IslandView()
        }
        .frame(width: NotchPanelController.panelSize.width, height: NotchPanelController.panelSize.height, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

struct IslandView: View {
    @ObservedObject private var model = IslandModel.shared
    @StateObject private var press = Box(false)

    private var shape: NotchShape { NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius) }

    var body: some View {
        let size = model.size
        shape
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                content
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(shape)
            }
            .shadow(color: .black.opacity(model.expanded || model.dropZone ? 0.45 : 0), radius: 14, y: 6)
            .overlay(alignment: .topTrailing) { bubble }
            .contentShape(shape)
            .onTapGesture {
                if press.v { press.v = false; return }
                model.tap()
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3).onEnded { _ in
                    press.v = true
                    model.expand()
                }
            )
            .simultaneousGesture(
                // Mouse users: drag up to collapse, drag sideways to hide (same as the swipes).
                DragGesture(minimumDistance: 14).onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    if abs(dx) > abs(dy) { model.swipe(.sideways) } else if dy < 0 { model.swipe(.up) } else { model.swipe(.down) }
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
                AirDrop.send(providers)
                return true
            }
            .animation(.island, value: size)
            .animation(.island, value: model.topRadius)
            .animation(.island, value: model.bottomRadius)
    }

    @ViewBuilder private var content: some View {
        let n = model.notch.size
        ZStack(alignment: .top) {
            if let alert = model.alert {
                AlertView(alert: alert, notch: n)
                    .id(alert.id)
                    .transition(.islandContent)
            } else if model.dropZone {
                AirDropZone(targeted: model.dropTargeted, notch: n)
                    .transition(.islandContent)
            } else if model.expanded, let p = model.primary {
                ActivityViews.expanded(p)
                    .padding(.top, n.height + 2)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id("expanded-\(p.rawValue)")
                    .transition(.islandContent)
            } else {
                CompactLayout(notch: n)
                    .transition(.islandContent)
            }
        }
    }

    @ViewBuilder private var bubble: some View {
        if model.showBubble, let s = model.secondary {
            let d = model.bubbleDiameter
            ZStack {
                Circle().fill(Color.black)
                ActivityViews.minimal(s)
            }
            .frame(width: d, height: d)
            .offset(x: d + IslandModel.bubbleGap)
            .onTapGesture { model.switchToSecondary() }
            .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
            .id("bubble-\(s.rawValue)")
        }
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.88)).animation(.islandSoft.delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

/// Compact presentation: leading content left of the camera, trailing content right of it.
struct CompactLayout: View {
    @ObservedObject private var model = IslandModel.shared
    let notch: CGSize

    var body: some View {
        let ear = max(0, (model.size.width - notch.width) / 2 - IslandModel.flare)
        HStack(spacing: 0) {
            Color.clear.frame(width: IslandModel.flare)
            ZStack {
                if !model.hidden, let p = model.primary {
                    ActivityViews.leading(p).id("lead-\(p.rawValue)").transition(.islandContent)
                }
            }
            .frame(width: ear, height: notch.height)
            Color.clear.frame(width: notch.width)
            HStack(spacing: 4) {
                if !model.hidden, let p = model.primary {
                    ActivityViews.trailing(p).id("trail-\(p.rawValue)").transition(.islandContent)
                        .frame(maxWidth: .infinity)
                }
                if model.privacyDot { PrivacyDot() }
            }
            .padding(.trailing, model.privacyDot ? 6 : 0)
            .frame(width: ear, height: notch.height)
            Color.clear.frame(width: IslandModel.flare)
        }
        .frame(height: notch.height)
    }
}

struct PrivacyDot: View {
    @ObservedObject private var model = IslandModel.shared
    var body: some View {
        Circle()
            .fill(model.cameraInUse ? Color.green : Color.orange)
            .frame(width: 6, height: 6)
    }
}

// MARK: - System alerts

struct AlertView: View {
    let alert: IslandAlert
    let notch: CGSize

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: IslandModel.flare)
            leading
                .frame(width: alert.earWidth, height: notch.height, alignment: .leading)
                .padding(.leading, 0)
            Color.clear.frame(width: notch.width)
            trailing
                .frame(width: alert.earWidth, height: notch.height, alignment: .trailing)
            Color.clear.frame(width: IslandModel.flare)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
    }

    @ViewBuilder private var leading: some View {
        switch alert.kind {
        case .charging:
            Label("Charging", systemImage: "bolt.fill").labelStyle(TightLabel(color: .green)).padding(.leading, 10)
        case .lowBattery:
            Label("Low Battery", systemImage: "battery.25percent").labelStyle(TightLabel(color: .red)).padding(.leading, 10)
        case .silent(let on):
            Image(systemName: on ? "bell.slash.fill" : "bell.fill")
                .foregroundStyle(on ? .red : .white)
                .symbolEffect(.bounce, value: on)
                .padding(.leading, 12)
        case .volume(let level):
            Image(systemName: level == 0 ? "speaker.slash.fill" : level < 0.33 ? "speaker.wave.1.fill" : level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .padding(.leading, 12)
        case .headphones(_, let symbol, _):
            Image(systemName: symbol).font(.system(size: 17)).padding(.leading, 10)
        case .unlocked:
            UnlockGlyph().padding(.leading, 8)
        case .downloaded:
            Label("Downloaded", systemImage: "arrow.down.circle.fill").labelStyle(TightLabel(color: .blue)).padding(.leading, 10)
        case .airdrop:
            Label("AirDrop", systemImage: "airplayaudio").labelStyle(TightLabel(color: .blue)).padding(.leading, 10)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch alert.kind {
        case .charging(let percent):
            HStack(spacing: 4) {
                Text("\(percent)%").foregroundStyle(.green).monospacedDigit()
                BatteryGlyph(percent: percent, color: .green)
            }.padding(.trailing, 10)
        case .lowBattery(let percent):
            HStack(spacing: 4) {
                Text("\(percent)%").foregroundStyle(.red).monospacedDigit()
                BatteryGlyph(percent: percent, color: .red)
            }.padding(.trailing, 10)
        case .silent(let on):
            Text(on ? "Silent" : "Ring").foregroundStyle(on ? .red : .white).padding(.trailing, 12)
        case .volume(let level):
            Capsule().fill(Color.white.opacity(0.22))
                .overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(Color.white).frame(width: max(6, g.size.width * CGFloat(level))) }
                }
                .frame(width: 78, height: 6)
                .padding(.trailing, 14)
                .animation(.islandSoft, value: level)
        case .headphones(let name, _, let batteries):
            if batteries.isEmpty {
                Text(name.count > 12 ? "Connected" : name).foregroundStyle(.white.opacity(0.9)).padding(.trailing, 10)
            } else {
                HStack(spacing: 6) {
                    ForEach(batteries, id: \.self) { b in BatteryRing(percent: b.percent, label: b.label) }
                }.padding(.trailing, 8)
            }
        case .unlocked:
            EmptyView()
        case .downloaded(let name):
            Text(name).truncationMode(.middle).foregroundStyle(.white.opacity(0.85)).padding(.trailing, 10)
        case .airdrop(let count):
            Text(count == 1 ? "1 file" : "\(count) files").foregroundStyle(.white.opacity(0.85)).padding(.trailing, 10)
        }
    }
}

struct TightLabel: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(color)
            configuration.title.foregroundStyle(.white)
        }
    }
}

struct BatteryGlyph: View {
    let percent: Int
    let color: Color
    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 3.5)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                .frame(width: 25, height: 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(2, 21 * CGFloat(percent) / 100), height: 8)
                        .padding(.leading, 2)
                }
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.45)).frame(width: 1.5, height: 4)
        }
    }
}

struct BatteryRing: View {
    let percent: Int
    let label: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(percent <= 20 ? Color.red : Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label.isEmpty ? "\(percent)" : label)
                .font(.system(size: 8, weight: .bold))
        }
        .frame(width: 20, height: 20)
        .help("\(label) \(percent)%")
    }
}

/// The padlock that springs open after unlocking (Face ID animation on iPhone).
struct UnlockGlyph: View {
    @StateObject private var opened = Box(false)
    var body: some View {
        Image(systemName: opened.v ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 14, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation(.island) { opened.v = true } }
            }
    }
}

// MARK: - AirDrop

struct AirDropZone: View {
    let targeted: Bool
    let notch: CGSize

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplayaudio")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(targeted ? .white : .blue)
                .symbolEffect(.pulse, isActive: !targeted)
            Text(targeted ? "Release to AirDrop" : "Drop here to AirDrop")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(targeted ? Color.blue : Color.white.opacity(0.3))
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.blue.opacity(targeted ? 0.25 : 0.06)))
        )
        .padding(.top, notch.height + 4)
        .padding([.horizontal, .bottom], 14)
        .animation(.islandSoft, value: targeted)
    }
}

@MainActor
enum AirDrop {
    static func send(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
            IslandModel.shared.show(.airdrop(count: urls.count))
        }
    }
}
