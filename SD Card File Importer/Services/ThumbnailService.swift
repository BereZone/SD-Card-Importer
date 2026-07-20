import Foundation
import QuickLookThumbnailing
import AppKit

actor ThumbnailService {
    static let shared = ThumbnailService()
    
    private let cache = NSCache<NSURL, NSImage>()
    private let generator = QLThumbnailGenerator.shared
    
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Only attempt for likely media files
        guard MediaTypes.allExts.contains(url.pathExtension.lowercased()) else { return nil }
        
        let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1.0, representationTypes: .thumbnail)
        
        do {
            let thumbnail = try await generator.generateBestRepresentation(for: req)
            let width = CGFloat(thumbnail.cgImage.width)
            let height = CGFloat(thumbnail.cgImage.height)
            let nsImage = NSImage(cgImage: thumbnail.cgImage, size: CGSize(width: width, height: height))
            cache.setObject(nsImage, forKey: url as NSURL)
            return nsImage
        } catch {
            print("Thumbnail generation failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
