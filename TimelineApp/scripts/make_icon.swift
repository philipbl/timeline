// Generates the app icon: a dark squircle with a timeline — colored
// event bars above and below, connected by leader lines to dots on the
// timeline.
// Usage: swift make_icon.swift /path/to/icon_1024.png

import AppKit
import CoreGraphics
import Foundation

let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!

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
    space: srgbSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    FileHandle.standardError.write(Data("Could not create context\n".utf8))
    exit(1)
}

// Big Sur-style icon: 824x824 rounded rect centered on a 1024 canvas
let inset: CGFloat = 100
let squircleRect = CGRect(
    x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = CGPath(
    roundedRect: squircleRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let backgroundGradient = CGGradient(
    colorsSpace: srgbSpace,
    colors: [srgb(0x303239), srgb(0x1E2025)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: size / 2, y: size - inset),
    end: CGPoint(x: size / 2, y: inset),
    options: [])
ctx.restoreGState()

/// Rounded event bar with a subtle top-lit gradient.
func drawEventBar(_ rect: CGRect, top: UInt32, bottom: UInt32) {
    let path = CGPath(
        roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: srgbSpace,
        colors: [srgb(top), srgb(bottom)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: [])
    ctx.restoreGState()
}

func drawLeader(x: CGFloat, from y0: CGFloat, to y1: CGFloat, color: UInt32) {
    ctx.setStrokeColor(srgb(color))
    ctx.setLineWidth(12)
    ctx.setLineCap(.butt)
    ctx.move(to: CGPoint(x: x, y: y0))
    ctx.addLine(to: CGPoint(x: x, y: y1))
    ctx.strokePath()
}

func drawDot(x: CGFloat, y: CGFloat, top: UInt32, bottom: UInt32) {
    let r: CGFloat = 42
    let path = CGPath(
        ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2),
        transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: srgbSpace,
        colors: [srgb(top), srgb(bottom)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: x, y: y + r),
        end: CGPoint(x: x, y: y - r),
        options: [])
    ctx.restoreGState()
}

let timelineY: CGFloat = 512
let gray: UInt32 = 0xC6C9D2

let orangeX: CGFloat = 330
let blueX: CGFloat = 512
let purpleX: CGFloat = 694

// Leader lines (under everything else)
drawLeader(x: blueX, from: timelineY, to: 700, color: 0x1E7CF0)  // blue, up
drawLeader(x: orangeX, from: 330, to: timelineY, color: 0xE8920A)  // orange, down
drawLeader(x: purpleX, from: 330, to: timelineY, color: 0x8E4BD6)  // purple, down

// Main timeline bar
ctx.setStrokeColor(srgb(gray))
ctx.setLineWidth(22)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 200, y: timelineY))
ctx.addLine(to: CGPoint(x: 824, y: timelineY))
ctx.strokePath()

// Event bars: blue on top; orange and purple on the bottom
drawEventBar(
    CGRect(x: blueX - 160, y: 700, width: 320, height: 78),
    top: 0x4D9BFF, bottom: 0x1E7CF0)
drawEventBar(
    CGRect(x: orangeX - 120, y: 252, width: 240, height: 78),
    top: 0xFFB340, bottom: 0xF59B0A)
drawEventBar(
    CGRect(x: purpleX - 150, y: 252, width: 300, height: 78),
    top: 0xB06EF8, bottom: 0x8E4BD6)

// Dots on the timeline (drawn last, over the bar and ticks)
drawDot(x: orangeX, y: timelineY, top: 0xFFB340, bottom: 0xF59B0A)
drawDot(x: blueX, y: timelineY, top: 0x4D9BFF, bottom: 0x1E7CF0)
drawDot(x: purpleX, y: timelineY, top: 0xB06EF8, bottom: 0x8E4BD6)

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "icon_1024.png"
try! data.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
