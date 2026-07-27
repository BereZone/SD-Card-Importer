import Foundation
import QuickLookThumbnailing
import AppKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    /// Decoded-bitmap budget for the cache, in bytes.
    ///
    /// Thumbnail memory is decoupled from source file size — a 200 MB RAW and a
    /// 3 MB JPEG decode to the same bitmap at a given display size — so the cap is
    /// a fixed budget in decoded bytes rather than anything derived from the files
    /// being imported.
    ///
    /// At the sizes this app actually requests (2x the display size): 9 KB per table
    /// row, 16 KB per list row, 160 KB per grid cell. So 256 MB holds ~1,600 grid
    /// cells or ~16,000 list rows — more than a card's worth in every layout, which
    /// means the budget only ever bites on genuinely huge cards.
    ///
    /// Deliberately no `countLimit`: any count cap tight enough to matter would bind
    /// before the byte budget in every layout, evicting list rows at ~10 MB of real
    /// usage and making the budget decorative. The per-entry bookkeeping a count cap
    /// would bound is a few hundred KB at these numbers — not worth the eviction.
    private static let byteBudget = 256 * 1024 * 1024

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = ThumbnailService.byteBudget
        return c
    }()

    private let generator = QLThumbnailGenerator.shared

    /// The requested size is part of the key: the same file renders at 24pt in the
    /// table and up to 200pt in the grid, and keying on the URL alone handed the
    /// first-generated size back to every other call site.
    private func cacheKey(for url: URL, size: CGSize) -> NSString {
        "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = cacheKey(for: url, size: size)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Only attempt for likely media files
        guard MediaTypes.allExts.contains(url.pathExtension.lowercased()) else { return nil }

        let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1.0, representationTypes: .thumbnail)

        do {
            let thumbnail = try await generator.generateBestRepresentation(for: req)
            let cgImage = thumbnail.cgImage
            let width = cgImage.width
            let height = cgImage.height
            let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
            // Supplying the decoded bitmap size as the cost is what makes
            // `totalCostLimit` meaningful — without it NSCache has no idea how large
            // the entries are and can only fall back on the memory-pressure purge.
            cache.setObject(nsImage, forKey: key, cost: width * height * 4)
            return nsImage
        } catch {
            print("Thumbnail generation failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Drops every cached bitmap. Called when the candidate list is replaced so a
    /// rescan or an eject doesn't keep the previous card's thumbnails alive.
    func clear() {
        cache.removeAllObjects()
    }
}
