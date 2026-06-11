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

// Timeline motif
let barY: CGFloat = 430
let barStart = pageX + 96
let barEnd = pageX + pageWidth - 96

ctx.setStrokeColor(srgb(0x9B5DE5))
ctx.setLineWidth(26)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: pageX + 290, y: 560))
ctx.addLine(to: CGPoint(x: pageX + 540, y: 560))
ctx.strokePath()

ctx.setStrokeColor(srgb(0x55555E))
ctx.setLineWidth(18)
ctx.move(to: CGPoint(x: barStart, y: barY))
ctx.addLine(to: CGPoint(x: barEnd, y: barY))
ctx.strokePath()

let dots: [(CGFloat, UInt32)] = [
    (pageX + 180, 0xFF6B6B),
    (pageX + 352, 0x3A86FF),
    (pageX + 524, 0x00A878),
]
for (x, hex) in dots {
    ctx.setFillColor(srgb(hex))
    let r: CGFloat = 34
    ctx.fillEllipse(in: CGRect(x: x - r, y: barY - r, width: r * 2, height: r * 2))
}

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "doc_1024.png"
try! data.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
