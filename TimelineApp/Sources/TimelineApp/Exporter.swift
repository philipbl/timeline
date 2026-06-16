import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum Exporter {
    enum ExportError: LocalizedError {
        case contextCreationFailed

        var errorDescription: String? { "Could not create a graphics context." }
    }

    /// Paged, paper-style PDF — same as the Python CLI output, title
    /// repeated on every page.
    static func pdfData(
        for config: TimelineConfig, includeGenerated: Bool = false
    ) throws -> Data {
        let renderer = TimelineRenderer(
            config: config, layout: .paged, theme: .light,
            includeGenerated: includeGenerated)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: TimelineRenderer.pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw ExportError.contextCreationFailed }

        for page in 0..<renderer.pageCount {
            ctx.beginPDFPage(nil)
            renderer.drawPage(page, in: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Bitmap of the continuous (title-once) layout for the live preview.
    /// Scale chosen by the caller to match the current zoom level.
    static func continuousImage(
        for config: TimelineConfig, theme: TimelineRenderer.Theme,
        background: CGColor? = nil, scale: CGFloat = 2, showToday: Bool = false
    ) -> CGImage? {
        let renderer = TimelineRenderer(
            config: config, layout: .continuous, theme: theme, showToday: showToday)
        let size = renderer.canvasSize
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        if let background {
            ctx.setFillColor(background)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(true)
        renderer.drawPage(0, in: ctx)
        return ctx.makeImage()
    }

    /// Background hex used by dark renders (preview canvas and dark PNG).
    static let darkBackgroundHex = "#1B1B20"

    /// PNG export: one continuous image, title once.
    /// Scale 1 = 72 dpi, 2 = 144 dpi, 4 = 288 dpi.
    static func writePNG(
        for config: TimelineConfig, to url: URL, scale: CGFloat = 2,
        includeGenerated: Bool = false, dark: Bool = false
    ) throws {
        let data = try pngData(
            for: config, scale: scale,
            includeGenerated: includeGenerated, dark: dark)
        try data.write(to: url)
    }

    /// Rendered PNG as in-memory data — for Share and drag-and-drop, which
    /// produce the bytes lazily (only when a destination is chosen).
    static func pngData(
        for config: TimelineConfig, scale: CGFloat = 2,
        includeGenerated: Bool = false, dark: Bool = false
    ) throws -> Data {
        let renderer = TimelineRenderer(
            config: config, layout: .continuous, theme: dark ? .dark : .light,
            includeGenerated: includeGenerated)
        let size = renderer.canvasSize
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ExportError.contextCreationFailed }

        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(
            dark ? TimelineRenderer.cg(darkBackgroundHex) : .white)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(true)
        renderer.drawPage(0, in: ctx)

        guard let image = ctx.makeImage() else {
            throw ExportError.contextCreationFailed
        }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = size  // points, so the PNG reports its dpi correctly
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.contextCreationFailed
        }
        return data
    }

    /// Mean per-channel difference between two PNGs, as a percentage.
    /// Returns nil if either image fails to load or sizes differ.
    static func imageDifferencePercent(_ urlA: URL, _ urlB: URL) -> Double? {
        func pixels(_ url: URL) -> (data: [UInt8], width: Int, height: Int)? {
            guard let image = NSImage(contentsOf: url)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
            let width = image.width
            let height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            guard let ctx = CGContext(
                data: &data, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return (data, width, height)
        }

        guard let a = pixels(urlA), let b = pixels(urlB),
              a.width == b.width, a.height == b.height
        else { return nil }

        var total: UInt64 = 0
        for i in 0..<a.data.count {
            total += UInt64(abs(Int(a.data[i]) - Int(b.data[i])))
        }
        return Double(total) / Double(a.data.count) / 255 * 100
    }
}
