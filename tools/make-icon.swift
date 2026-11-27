// Draws the app icon (1024 px) to the path given as the first argument.
// Usage: swift tools/make-icon.swift Resources/icon-1024.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824 px rounded square centred in 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(tilePath)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.30, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// The island: a black pill hanging from the top edge.
let island = CGRect(x: 212, y: 700, width: 600, height: 300)
ctx.setFillColor(NSColor.black.cgColor)
ctx.addPath(CGPath(roundedRect: island, cornerWidth: 90, cornerHeight: 90, transform: nil))
ctx.fillPath()

// Left: orange timer ring. Right: green waveform.
ctx.setStrokeColor(NSColor.systemOrange.cgColor)
ctx.setLineWidth(14)
ctx.addArc(center: CGPoint(x: 315, y: 790), radius: 38, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.5, clockwise: true)
ctx.strokePath()
ctx.setFillColor(NSColor.systemGreen.cgColor)
for (i, h) in [40.0, 76, 52, 90, 34].enumerated() {
    let x = 640 + CGFloat(i) * 26
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 790 - h / 2, width: 14, height: h), cornerWidth: 7, cornerHeight: 7, transform: nil))
}
ctx.fillPath()

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
