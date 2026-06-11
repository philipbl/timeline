import QuickLookUI

/// Quick Look preview for .timeline documents: renders the continuous
/// (title-once) layout as vector content directly into the preview.
class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let text = try String(contentsOf: request.fileURL, encoding: .utf8)
        let config = try ConfigYAML.parse(text)
        let renderer = TimelineRenderer(config: config, layout: .continuous, theme: .light)
        let size = renderer.canvasSize

        return QLPreviewReply(contextSize: size, isBitmap: false) { context, _ in
            context.setFillColor(TimelineRenderer.cg("#FFFFFF"))
            context.fill(CGRect(origin: .zero, size: size))
            renderer.drawPage(0, in: context)
        }
    }
}
