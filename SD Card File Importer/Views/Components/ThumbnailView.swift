import SwiftUI

struct ThumbnailView: View {
    let url: URL
    /// The long edge. The short edge follows from the image's own aspect ratio.
    let size: CGFloat
    let show: Bool
    /// Force a square box. Used by the dense list, where ragged row heights
    /// would cost more than orientation is worth at 28pt.
    var fixedSquare: Bool = false

    @State private var image: NSImage?
    @State private var failed: Bool = false

    private var isVideo: Bool {
        MediaTypes.isVideoExtension(url)
    }

    /// Width over height. Before the image arrives this is 3:2 — the aspect of
    /// most stills cameras — so the grid does not visibly re-flow on load.
    private var aspect: CGFloat {
        guard !fixedSquare else { return 1 }
        guard let image, image.size.height > 0 else { return 3.0 / 2.0 }
        return image.size.width / image.size.height
    }

    private var boxSize: CGSize {
        if fixedSquare { return CGSize(width: size, height: size) }
        return aspect >= 1
            ? CGSize(width: size, height: size / aspect)   // landscape
            : CGSize(width: size * aspect, height: size)   // portrait
    }

    var body: some View {
        Group {
            if !show {
                fallbackIcon
            } else if let image {
                // .fill inside an already correctly-proportioned box, so the
                // frame matches the photograph instead of cropping it square.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: boxSize.width, height: boxSize.height)
                    .clipped()
            } else if failed {
                fallbackIcon
            } else {
                ZStack {
                    Rectangle().fill(Color(nsColor: .quaternaryLabelColor))
                    ProgressView().controlSize(.small)
                }
                .frame(width: boxSize.width, height: boxSize.height)
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

    /// Occupies the same box a real thumbnail would, so the grid does not reflow
    /// as images arrive. The old fallback was a tinted circle that used the
    /// app's invented brand colours to mean "photo" and "video".
    private var fallbackIcon: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .quaternaryLabelColor))
            Image(systemName: isVideo ? "video" : "photo")
                .font(.system(size: max(12, min(boxSize.width, boxSize.height) * 0.32)))
                .foregroundStyle(.secondary)
        }
        .frame(width: boxSize.width, height: boxSize.height)
    }

    private func loadThumbnail() async {
        // Debounce so fast scrolling does not start a task per cell it passes.
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }

        // Square request; QuickLook preserves the source aspect within it, and
        // the view then sizes its box to whatever comes back.
        let targetSize = CGSize(width: size * 2, height: size * 2)
        if let img = await ThumbnailService.shared.thumbnail(for: url, size: targetSize) {
            self.image = img
        } else {
            self.failed = true
        }
    }
}
