#!/usr/bin/env swift

// Renders the AgentWatch app icon at every macOS-required resolution and
// packages them into Resources/AppIcon.icns.
//
// Concept: a glowing C-arc in cyan→magenta angular gradient on a dark squircle,
// with a gold pulse-dot at the center. Pure Core Graphics — no SwiftUI runloop
// dependency, runs cleanly as `swift tools/make-icon.swift`.
//
// Usage from the repo root:
//   swift tools/make-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit  // only for CGColor convenience; no runloop needed

// MARK: - Palette (mirrors Sources/AgentWatch/UI/Theme.swift)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let darkInk1    = rgb(  6,   8,  14)
let darkInk2    = rgb( 18,  14,  32)
let neonCyan    = rgb(  0, 240, 255)
let neonMagenta = rgb(255,   0, 229)
let dpGold      = rgb(255, 200,  60)
let cs          = CGColorSpaceCreateDeviceRGB()

// Squircle (rounded-rect with continuous corners). CG only has rounded rects,
// not true squircles, but at the radius we use it reads close enough.
func squirclePath(rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
}

// MARK: - Render one PNG at a given pixel size

func renderIcon(pixelSize: Int) -> Data? {
    let s = CGFloat(pixelSize)
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Clear
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // -- Squircle background fill --
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.225
    ctx.saveGState()
    ctx.addPath(squirclePath(rect: bgRect, cornerRadius: cornerRadius))
    ctx.clip()

    if let bgGradient = CGGradient(
        colorsSpace: cs,
        colors: [darkInk1, darkInk2] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: 0, y: s),         // top-left in CG coordinates
            end:   CGPoint(x: s, y: 0),         // bottom-right
            options: []
        )
    }

    // -- Cyan corner glow (top-left) --
    if let cyanGlow = CGGradient(
        colorsSpace: cs,
        colors: [neonCyan.copy(alpha: 0.50)!, neonCyan.copy(alpha: 0.0)!] as CFArray,
        locations: [0.0, 1.0]
    ) {
        // CG y is flipped: top-left corresponds to (0, s)
        ctx.drawRadialGradient(
            cyanGlow,
            startCenter: CGPoint(x: 0, y: s), startRadius: 0,
            endCenter:   CGPoint(x: 0, y: s), endRadius:   s * 0.75,
            options: []
        )
    }

    // -- Magenta corner glow (bottom-right) --
    if let magGlow = CGGradient(
        colorsSpace: cs,
        colors: [neonMagenta.copy(alpha: 0.40)!, neonMagenta.copy(alpha: 0.0)!] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            magGlow,
            startCenter: CGPoint(x: s, y: 0), startRadius: 0,
            endCenter:   CGPoint(x: s, y: 0), endRadius:   s * 0.75,
            options: []
        )
    }

    ctx.restoreGState()

    // -- The C arc --
    // Stroked partial-circle in a cyan→magenta→cyan colour. CG doesn't have
    // angular gradients, so we approximate by drawing the ring twice with
    // different colours and a soft compositing trick: first a magenta ring,
    // then a cyan arc on top covering the upper-left half.
    let center = CGPoint(x: s / 2, y: s / 2)
    let radius = s / 2 - s * 0.18
    let lineWidth = s * 0.085
    let startAngle: CGFloat = 0.92 * 2 * .pi - .pi / 2     // matches SwiftUI rotation(135) + trim
    let endAngle:   CGFloat = 0.08 * 2 * .pi - .pi / 2 + 2 * .pi
    // Outer glow underlay (soft magenta blur via shadow trick)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.07, color: neonMagenta.copy(alpha: 0.6))
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(neonMagenta)
    ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Cyan glow underlay
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: neonCyan.copy(alpha: 0.7))
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(neonCyan)
    ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + (endAngle - startAngle) * 0.55, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Crisp ring: magenta full arc, cyan half on top
    ctx.saveGState()
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(neonMagenta)
    ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(neonCyan)
    ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + (endAngle - startAngle) * 0.5, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // -- Centre gold dot --
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.085, color: dpGold.copy(alpha: 0.85))
    ctx.setFillColor(dpGold)
    let dotR = s * 0.065
    ctx.fillEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2))
    ctx.restoreGState()

    // Crisp gold core (no shadow)
    ctx.setFillColor(dpGold)
    let coreR = s * 0.035
    ctx.fillEllipse(in: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2))

    guard let cgImage = ctx.makeImage() else { return nil }
    let mutableData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return mutableData as Data
}

// MARK: - Driver

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let resources = cwd.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (logical pt size, scale, filename)
let entries: [(Int, Int, String)] = [
    ( 16, 1, "icon_16x16.png"),
    ( 16, 2, "icon_16x16@2x.png"),
    ( 32, 1, "icon_32x32.png"),
    ( 32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

for (size, scale, name) in entries {
    let pixels = size * scale
    guard let data = renderIcon(pixelSize: pixels) else {
        print("render failed for \(name)"); exit(1)
    }
    try data.write(to: iconset.appendingPathComponent(name))
    print("  wrote \(name) — \(pixels)px")
}

// iconutil → AppIcon.icns
let icns = resources.appendingPathComponent("AppIcon.icns")
try? fm.removeItem(at: icns)
let p = Process()
p.launchPath = "/usr/bin/iconutil"
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else {
    print("iconutil failed (\(p.terminationStatus))"); exit(1)
}

print("\n==> Resources/AppIcon.icns")
if let attrs = try? fm.attributesOfItem(atPath: icns.path), let bytes = attrs[.size] as? Int {
    print("    \(bytes) bytes")
}

// Clean up the .iconset directory; commit the .icns only.
try? fm.removeItem(at: iconset)
