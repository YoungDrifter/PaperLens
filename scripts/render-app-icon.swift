#!/usr/bin/env swift
// Editable vector master for PaperLens. Regenerate all macOS PNG slots with:
// swift scripts/render-app-icon.swift /absolute/path/to/project
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(white: r * 0.2126 + g * 0.7152 + b * 0.0722, alpha: a) }
func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)!.draw(in: path, angle: 90)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }
func stroke(_ path: NSBezierPath, _ ink: NSColor, _ width: CGFloat) { ink.setStroke(); path.lineWidth = width; path.stroke() }
func shadow(_ blur: CGFloat, _ offset: NSSize, _ opacity: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = offset
    s.shadowColor = color(0.08, 0.28, 0.48, opacity); s.set(); draw()
    NSGraphicsContext.restoreGraphicsState()
}
func artwork() {
    let base = rounded(NSRect(x: 80, y: 80, width: 864, height: 864), 194)
    shadow(24, NSSize(width: 0, height: -10), 0.18) { gradient(base, color(0.97, 0.97, 0.97), color(0.81, 0.81, 0.81)) }
    stroke(base, color(1, 1, 1, 0.72), 3)
    let glow = rounded(NSRect(x: 92, y: 500, width: 840, height: 432), 185)
    NSGraphicsContext.saveGraphicsState(); base.addClip()
    gradient(glow, color(1, 1, 1, 0.35), color(1, 1, 1, 0))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: 506, yBy: 522); t.rotate(byDegrees: -8); t.translateX(by: -506, yBy: -522); t.concat()
    let back = rounded(NSRect(x: 307, y: 248, width: 434, height: 556), 48)
    shadow(16, NSSize(width: 0, height: -10), 0.16) { gradient(back, color(0.99, 1, 1, 0.83), color(0.74, 0.88, 0.98, 0.92)) }
    stroke(back, color(1, 1, 1, 0.75), 3)
    NSGraphicsContext.restoreGraphicsState()

    let page = rounded(NSRect(x: 220, y: 247, width: 438, height: 579), 48)
    shadow(24, NSSize(width: 0, height: -14), 0.19) { gradient(page, color(1, 1, 1), color(0.90, 0.96, 1)) }
    stroke(page, color(1, 1, 1, 0.95), 3)
    gradient(rounded(NSRect(x: 279, y: 725, width: 174, height: 32), 16), color(0.33, 0.67, 0.97), color(0.13, 0.48, 0.84))
    for (y, width) in [(CGFloat(638), CGFloat(271)), (580, 239), (522, 269)] {
        color(0.54, 0.70, 0.83, 0.54).setFill()
        rounded(NSRect(x: 279, y: y, width: width, height: 17), 8.5).fill()
    }
    color(0.32, 0.71, 1, 0.23).setFill()
    rounded(NSRect(x: 270, y: 433, width: 289, height: 39), 12).fill()
    color(0.24, 0.53, 0.77, 0.64).setFill()
    rounded(NSRect(x: 279, y: 444, width: 228, height: 16), 8).fill()

    let handle = NSBezierPath(); handle.move(to: NSPoint(x: 769, y: 270)); handle.line(to: NSPoint(x: 837, y: 199)); handle.lineCapStyle = .round
    shadow(12, NSSize(width: 0, height: -7), 0.22) { stroke(handle, color(0.2, 0.2, 0.2), 66) }
    let shine = NSBezierPath(); shine.move(to: NSPoint(x: 785, y: 263)); shine.line(to: NSPoint(x: 833, y: 213)); shine.lineCapStyle = .round
    stroke(shine, color(0.60, 0.82, 1, 0.62), 8)
    let lens = NSBezierPath(ovalIn: NSRect(x: 531, y: 272, width: 286, height: 286))
    shadow(20, NSSize(width: 0, height: -10), 0.23) { gradient(lens, color(0.98, 1, 1, 0.97), color(0.70, 0.89, 1, 0.98)) }
    stroke(lens, color(0.2, 0.2, 0.2), 25)
    let inside = NSBezierPath(ovalIn: NSRect(x: 550, y: 291, width: 248, height: 248))
    stroke(inside, color(1, 1, 1, 0.75), 4)
    color(0.27, 0.54, 0.75, 0.36).setFill()
    for (y, width) in [(CGFloat(438), CGFloat(146)), (392, 111), (346, 131)] {
        rounded(NSRect(x: 601, y: y, width: width, height: 16), 8).fill()
    }
    let reflection = NSBezierPath(); reflection.move(to: NSPoint(x: 573, y: 452)); reflection.curve(to: NSPoint(x: 658, y: 514), controlPoint1: NSPoint(x: 582, y: 491), controlPoint2: NSPoint(x: 617, y: 515)); reflection.lineCapStyle = .round
    stroke(reflection, color(1, 1, 1, 0.90), 12)
}
let assets = root.appendingPathComponent("PaperLens/Assets.xcassets/AppIcon.appiconset")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat(); artwork()
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: assets.appendingPathComponent("icon_\(size).png"))
    if size == 1024 { try png.write(to: root.appendingPathComponent("PaperLens/Icon/icon_1024.png")) }
}
print("Rendered PaperLens icon: 16–1024 px")
