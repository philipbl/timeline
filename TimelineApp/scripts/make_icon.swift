// Generates the app icon: a dark squircle with the timeline motif.
// Usage: swift make_icon.swift /path/to/icon_1024.png

import AppKit
import CoreGraphics
import Foundation

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

let size: CGFloat = 1024
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    FileHandle.standardError.write(Data("Could not create context\n".utf8))
    exit(1)
}

// Big Sur-style icon: 824x824 rounded rect centered on a 1024 canvas
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [srgb(0x2A2A35), srgb(0x17171C)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: size / 2, y: size - inset),
    end: CGPoint(x: size / 2, y: inset),
    options: [])
ctx.restoreGState()

let barY: CGFloat = 470
let barStart: CGFloat = 240
let barEnd: CGFloat = 784

// Range bar floating above the timeline
ctx.setStrokeColor(srgb(0x9B5DE5))
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 400, y: 620))
ctx.addLine(to: CGPoint(x: 660, y: 620))
ctx.strokePath()

// Main timeline bar
ctx.setStrokeColor(srgb(0xE8E8EE))
ctx.setLineWidth(22)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: barStart, y: barY))
ctx.addLine(to: CGPoint(x: barEnd, y: barY))
ctx.strokePath()

// Ticks
ctx.setStrokeColor(srgb(0xE8E8EE, alpha: 0.55))
ctx.setLineWidth(10)
ctx.setLineCap(.round)
for i in 0..<5 {
    let x = barStart + CGFloat(i) * (barEnd - barStart) / 4
    ctx.move(to: CGPoint(x: x, y: barY - 36))
    ctx.addLine(to: CGPoint(x: x, y: barY + 36))
    ctx.strokePath()
}

// Event dots in the palette colors
let dots: [(CGFloat, UInt32)] = [
    (376, 0xFF6B6B),  // coral
    (512, 0x3A86FF),  // bright blue
    (648, 0x00A878),  // jade
]
for (x, hex) in dots {
    ctx.setFillColor(srgb(hex))
    let r: CGFloat = 44
    ctx.fillEllipse(in: CGRect(x: x - r, y: barY - r, width: r * 2, height: r * 2))
}

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "icon_1024.png"
try! data.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
