import AppKit

/// Where the camera housing is. Content drawn inside `notchRect` is invisible on notched Macs
/// (there are no pixels there), so the island grows "ears" left and right of it.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var size: CGSize
    var hasNotch: Bool

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                 size: CGSize(width: 180, height: 32), hasNotch: false)
        }
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = frame.width - left - right
            return NotchGeometry(screenFrame: frame,
                                 size: CGSize(width: max(width, 120), height: screen.safeAreaInsets.top),
                                 hasNotch: true)
        }
        // No notch (external display or lid closed): draw a virtual one the size of a MacBook notch.
        let menuBar = max(frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(screenFrame: frame, size: CGSize(width: 180, height: menuBar), hasNotch: false)
    }
}
