#!/usr/bin/env swift
//
// Renders the app icon (a coral rounded badge with a white gauge glyph) into
// Resources/AppIcon.icns. Self-contained: uses AppKit + iconutil, no assets.
//
// Run from the repo root:  swift scripts/make-icon.swift
//
import AppKit
import Foundation

let brand = NSColor(srgbRed: 0.85, green: 0.46, blue: 0.34, alpha: 1)
let symbolName = "gauge.with.dots.needle.bottom.50percent"

/// One PNG at `px`×`px`, rendered into an off-screen bitmap (works headless).
func renderPNG(_ px: Int) -> Data? {
    let dim = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Rounded-rect badge with a little breathing room (macOS icon grid).
    let inset = dim * 0.09
    let rect = NSRect(x: inset, y: inset, width: dim - 2 * inset, height: dim - 2 * inset)
    let radius = rect.width * 0.2237 // Apple's continuous-corner ratio
    let badge = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    brand.setFill()
    badge.fill()

    // White gauge glyph, centered.
    let config = NSImage.SymbolConfiguration(pointSize: dim * 0.5, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let gs = glyph.size
        glyph.draw(
            at: NSPoint(x: (dim - gs.width) / 2, y: (dim - gs.height) / 2),
            from: .zero, operation: .sourceOver, fraction: 1
        )
    }

    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// iconset layout expected by `iconutil`.
let entries: [(px: Int, name: String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

let fm = FileManager.default
let tmp = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: tmp)
try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)

for entry in entries {
    guard let png = renderPNG(entry.px) else {
        FileHandle.standardError.write(Data("failed to render \(entry.name)\n".utf8))
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: tmp + "/" + entry.name))
}

try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tmp, "-o", "Resources/AppIcon.icns"]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus == 0 {
    print("Wrote Resources/AppIcon.icns")
} else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
