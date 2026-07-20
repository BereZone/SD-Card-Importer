import Foundation

/// Single source of truth for which file extensions the app treats as media,
/// and for photo/video categorization. Shared by the scanner, importer,
/// thumbnailer, and camera profiles so the lists can't drift apart.
enum MediaTypes {
    static let videoExts: Set<String> = ["mp4", "mov", "mxf", "mts", "m4v"]

    static let photoExts: Set<String> = [
        "jpg", "jpeg", "heic", "png", "dng",
        "arw",        // Sony
        "cr2", "cr3", // Canon
        "nef", "nrw", // Nikon
        "raf",        // Fujifilm
        "rw2",        // Panasonic
        "orf",        // Olympus/OM System
        "gpr"         // GoPro
    ]

    static let allExts: Set<String> = videoExts.union(photoExts)

    static func isVideoExtension(_ url: URL) -> Bool {
        videoExts.contains(url.pathExtension.lowercased())
    }

    /// Categorizes a file as video or photo for bucketing purposes.
    /// DJI hyperlapse/timelapse folders contain stills that belong with videos,
    /// and panorama folders contain videos that belong with photos.
    static func isVideoCategory(_ url: URL) -> Bool {
        let p = url.path.lowercased()
        if p.contains("hyperlapse") || p.contains("timelapse") { return true }
        if p.contains("panorama") || p.contains("pano") { return false }
        return isVideoExtension(url)
    }
}
