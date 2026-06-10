import SwiftUI

/// Live-rendered timeline pages, styled like Preview.app: gray backdrop,
/// white pages with a soft shadow.
struct PreviewView: View {
    let config: TimelineConfig

    var body: some View {
        let pageCount = TimelineRenderer(config: config).pageCount

        ScrollView([.vertical]) {
            VStack(spacing: 24) {
                ForEach(0..<pageCount, id: \.self) { page in
                    if let image = Exporter.pageImage(for: config, page: page) {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .aspectRatio(
                                TimelineRenderer.pageSize.width
                                    / TimelineRenderer.pageSize.height,
                                contentMode: .fit)
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
