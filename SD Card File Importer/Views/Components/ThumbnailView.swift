import SwiftUI

struct ThumbnailView: View {
    let url: URL
    let size: CGFloat
    let show: Bool
    
    @State private var image: NSImage?
    @State private var failed: Bool = false
    
    var body: some View {
        Group {
            if !show {
                fallbackIcon
            } else if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if failed {
                fallbackIcon
            } else {
                ZStack {
                    fallbackIcon.opacity(0.3)
                    ProgressView()
                        .controlSize(.small)
                }
                .task(id: url) {
                    await loadThumbnail()
                }
            }
        }
    }
    

    
    private var fallbackIcon: some View {
        let isVideo = ["mp4", "mov", "mxf", "mts", "m4v"].contains(url.pathExtension.lowercased())
        
        return ZStack {
            Circle()
                .fill(isVideo ? Color.accentSecondary.opacity(0.2) : Color.successGreen.opacity(0.2))
                .frame(width: size, height: size)
            
            Image(systemName: isVideo ? "video.fill" : "photo.fill")
                .font(.system(size: size * 0.45))
                .foregroundColor(isVideo ? .accentSecondary : .successGreen)
        }
    }
    
    private func loadThumbnail() async {
        // Debounce: Wait a minimal amount to avoid starting tasks during fast scroll
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        if Task.isCancelled { return }
        
        // Double size for retina
        let targetSize = CGSize(width: size * 2, height: size * 2)
        if let img = await ThumbnailService.shared.thumbnail(for: url, size: targetSize) {
            self.image = img
        } else {
            self.failed = true
        }
    }
}
