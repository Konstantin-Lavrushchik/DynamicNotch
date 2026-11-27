import AppKit
import SwiftUI

/// Borderless, transparent panel over the notch. It only takes mouse events while the pointer
/// is over the island itself, so the rest of the panel never blocks the menu bar or apps.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController {
    static let panelSize = CGSize(width: 760, height: 300)

    private let panel: NotchPanel
    private let model = IslandModel.shared
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var scrollAccum = CGSize.zero
    private var scrollLocked = false

    init() {
        panel = NotchPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: IslandRootView())
        host.frame = CGRect(origin: .zero, size: Self.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        installMonitors()
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        model.notch = NotchGeometry.current()
        let screen = model.notch.screenFrame
        let origin = CGPoint(x: screen.midX - Self.panelSize.width / 2, y: screen.maxY - Self.panelSize.height)
        panel.setFrame(CGRect(origin: origin, size: Self.panelSize), display: true)
    }

    // MARK: - Mouse

    private func installMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobal(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .scrollWheel, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleLocal(event) ?? event }
        }
        monitors = [global as Any, local as Any]
    }

    private func handleGlobal(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            if model.expanded && !isInside() { model.collapse() }
        case .leftMouseDragged:
            updateDropZone()
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
        updatePointer()
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .scrollWheel:
            handleScroll(event)
            return nil
        case .rightMouseDown:
            if isInside() { AppMenu.popUpAtMouse(); return nil }
        case .leftMouseDragged:
            updateDropZone()
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
        updatePointer()
        return event
    }

    private func isInside(padding: CGFloat = 0) -> Bool {
        var rect = model.hitRect
        rect = rect.insetBy(dx: -padding, dy: -padding)
        rect.size.height += 2 // NSRect excludes maxY; the pointer can sit on the very top row.
        return rect.contains(NSEvent.mouseLocation)
    }

    private func updatePointer() {
        let inside = isInside()
        panel.ignoresMouseEvents = !(inside || model.dropZone)
        if inside != model.mouseInside { model.mouseInside = inside }

        if inside {
            leaveTask?.cancel(); leaveTask = nil
            if Prefs.on(Prefs.expandOnHover), !model.expanded, model.primary != nil, !model.hidden, hoverTask == nil {
                hoverTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, let self, self.isInside() else { return }
                    self.model.expand()
                    self.hoverTask = nil
                }
            }
        } else {
            hoverTask?.cancel(); hoverTask = nil
            // Like tapping outside on iPhone: leaving the expanded island collapses it.
            if model.expanded && !model.holdOpen && leaveTask == nil {
                leaveTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled, let self else { return }
                    if !self.isInside() { self.model.collapse() }
                    self.leaveTask = nil
                }
            }
        }
    }

    // MARK: - Drag a file to the notch → AirDrop

    private func updateDropZone() {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount,
              pasteboard.types?.contains(.fileURL) == true else { return }
        let screen = model.notch.screenFrame
        let zone = CGRect(x: screen.midX - 260, y: screen.maxY - 170, width: 520, height: 172)
        let near = zone.contains(NSEvent.mouseLocation)
        if near != model.dropZone { model.setDropZone(near) }
        panel.ignoresMouseEvents = !(near || isInside())
    }

    private func endDrag() {
        guard model.dropZone else { return }
        // Give SwiftUI's onDrop a moment to receive the files first.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.model.setDropZone(false)
            self?.dragChangeCount = NSPasteboard(name: .drag).changeCount
        }
    }

    // MARK: - Trackpad swipes on the island

    private func handleScroll(_ event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin {
            scrollAccum = .zero
            scrollLocked = false
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollAccum = .zero
            scrollLocked = false
            return
        }
        guard !scrollLocked, event.hasPreciseScrollingDeltas else { return }
        // Physical finger direction, independent of the natural-scrolling setting.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        scrollAccum.width += event.scrollingDeltaX * sign
        scrollAccum.height += event.scrollingDeltaY * sign
        let threshold: CGFloat = 28
        if abs(scrollAccum.width) > threshold && abs(scrollAccum.width) > abs(scrollAccum.height) {
            model.swipe(.sideways)
            scrollLocked = true
        } else if scrollAccum.height > threshold {
            model.swipe(.up)
            scrollLocked = true
        } else if scrollAccum.height < -threshold {
            model.swipe(.down)
            scrollLocked = true
        }
    }
}
