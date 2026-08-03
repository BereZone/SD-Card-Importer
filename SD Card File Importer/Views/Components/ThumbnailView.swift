import SwiftUI

struct ThumbnailView: View {
    let url: URL
    let size: CGFloat
    let show: Bool

    @State private var image: NSImage?
    @State private var failed: Bool = false

    private var isVideo: Bool {
        MediaTypes.isVideoExtension(url)
    }

    var body: some View {
        Group {
            if !show {
                fallbackIcon
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else if failed {
                fallbackIcon
            } else {
                ZStack {
                    Rectangle().fill(Color(nsColor: .quaternaryLabelColor))
                    ProgressView().controlSize(.small)
                }
                .frame(width: size, height: size)
                .task(id: url) { await loadThumbnail() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            // A still and a clip are different things to a photographer, and the
            // difference must survive at thumbnail size and in greyscale — so it
            // is a badge, not a tint.
            if isVideo {
                Image(systemName: "video.fill")
                    .font(.system(.caption2))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                    .padding(3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    /// Fills the same square as a real thumbnail so the grid never reflows as
    /// images arrive. The old fallback was a tinted circle that used the app's
    /// invented brand colours to mean "photo" and "video".
    private var fallbackIcon: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .quaternaryLabelColor))
            Image(systemName: isVideo ? "video" : "photo")
                .font(.system(size: max(12, size * 0.32)))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }

    private func loadThumbnail() async {
        // Debounce so fast scrolling does not start a task per cell it passes.
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }

        let targetSize = CGSize(width: size * 2, height: size * 2)
        if let img = await ThumbnailService.shared.thumbnail(for: url, size: targetSize) {
            self.image = img
        } else {
            self.failed = true
        }
    }
}
