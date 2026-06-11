// Generates the .timeline document icon: a white page with a folded
// corner and the timeline motif.
// Usage: swift make_doc_icon.swift /path/to/doc_1024.png

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
else { exit(1) }

// Page: classic document proportions, centered
let pageWidth: CGFloat = 704
let pageHeight: CGFloat = 896
let pageX = (size - pageWidth) / 2
let pageY = (size - pageHeight) / 2
let fold: CGFloat = 176
let radius: CGFloat = 28

// Page outline with folded top-right corner
let page = CGMutablePath()
page.move(to: CGPoint(x: pageX + radius, y: pageY))
page.addLine(to: CGPoint(x: pageX + pageWidth - radius, y: pageY))
page.addQuadCurve(
    to: CGPoint(x: pageX + pageWidth, y: pageY + radius),
    control: CGPoint(x: pageX + pageWidth, y: pageY))
page.addLine(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - fold))
page.addLine(to: CGPoint(x: pageX + pageWidth - fold, y: pageY + pageHeight))
page.addLine(to: CGPoint(x: pageX + radius, y: pageY + pageHeight))
page.addQuadCurve(
    to: CGPoint(x: pageX, y: pageY + pageHeight - radius),
    control: CGPoint(x: pageX, y: pageY + pageHeight))
page.addLine(to: CGPoint(x: pageX, y: pageY + radius))
page.addQuadCurve(
    to: CGPoint(x: pageX + radius, y: pageY),
    control: CGPoint(x: pageX, y: pageY))
page.closeSubpath()

ctx.saveGState()
ctx.addPath(page)
ctx.clip()
let pageGradient = CGGradient(
    colorsSpace: srgbSpace,
    colors: [srgb(0xFFFFFF), srgb(0xF2F2F6)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    pageGradient,
    start: CGPoint(x: size / 2, y: pageY + pageHeight),
    end: CGPoint(x: size / 2, y: pageY),
    options: [])
ctx.restoreGState()

// Fold shadow triangle
ctx.setFillColor(srgb(0xC9CBD4))
ctx.move(to: CGPoint(x: pageX + pageWidth - fold, y: pageY + pageHeight))
ctx.addLine(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - fold))
ctx.addLine(
    to: CGPoint(x: pageX + pageWidth - fold, y: pageY + pageHeight - fold))
ctx.closePath()
ctx.fillPath()

// Page border
ctx.addPath(page)
ctx.setStrokeColor(srgb(0xB9BCC6))
ctx.setLineWidth(6)
ctx.strokePath()

// Timeline motif, matching the app icon: event bars above and below,
// connected by leader lines to dots on the timeline
func drawEventBar(_ rect: CGRect, top: UInt32, bottom: UInt32) {
    let path = CGPath(
        roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
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
    ctx.setLineWidth(10)
    ctx.setLineCap(.butt)
    ctx.move(to: CGPoint(x: x, y: y0))
    ctx.addLine(to: CGPoint(x: x, y: y1))
    ctx.strokePath()
}

func drawDot(x: CGFloat, y: CGFloat, top: UInt32, bottom: UInt32) {
    let r: CGFloat = 32
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

let timelineY: CGFloat = 500
let orangeX = pageX + 176
let blueX = pageX + 352
let purpleX = pageX + 528

// Leader lines under everything else
drawLeader(x: blueX, from: timelineY, to: 642, color: 0x1E7CF0)
drawLeader(x: orangeX, from: 358, to: timelineY, color: 0xE8920A)
drawLeader(x: purpleX, from: 358, to: timelineY, color: 0x8E4BD6)

// Main timeline bar (darker than the app icon's: white background)
ctx.setStrokeColor(srgb(0x8E929E))
ctx.setLineWidth(18)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: pageX + 88, y: timelineY))
ctx.addLine(to: CGPoint(x: pageX + pageWidth - 88, y: timelineY))
ctx.strokePath()

// Event bars: blue on top; orange and purple on the bottom
drawEventBar(
    CGRect(x: blueX - 128, y: 642, width: 256, height: 64),
    top: 0x4D9BFF, bottom: 0x1E7CF0)
drawEventBar(
    CGRect(x: orangeX - 96, y: 294, width: 192, height: 64),
    top: 0xFFB340, bottom: 0xF59B0A)
drawEventBar(
    CGRect(x: purpleX - 120, y: 294, width: 240, height: 64),
    top: 0xB06EF8, bottom: 0x8E4BD6)

// Dots on the timeline (drawn last, over the bar)
drawDot(x: orangeX, y: timelineY, top: 0xFFB340, bottom: 0xF59B0A)
drawDot(x: blueX, y: timelineY, top: 0x4D9BFF, bottom: 0x1E7CF0)
drawDot(x: purpleX, y: timelineY, top: 0xB06EF8, bottom: 0x8E4BD6)

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "doc_1024.png"
try! data.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
