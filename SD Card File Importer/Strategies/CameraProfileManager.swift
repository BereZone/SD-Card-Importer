import Foundation

struct CameraProfileManager {
    static let shared = CameraProfileManager()
    
    let profiles: [CameraProfile] = [
        DJIProfile(),
        SonyProfile(),
        CanonProfile(),
        NikonProfile(),
        PanasonicProfile(),
        FujifilmProfile(),
        GenericCameraProfile()
    ]
    
    func baseBucket(for url: URL) -> String? {
        for profile in profiles {
            if let matched = profile.match(url: url) {
                return matched.replacingOccurrences(of: " Videos", with: "")
                    .replacingOccurrences(of: " Pictures", with: "")
                    .replacingOccurrences(of: " Photos", with: "")
            }
        }
        return nil
    }

    func applyCategory(to baseBucket: String, url: URL) -> String {
        let cleanBase = baseBucket.replacingOccurrences(of: " Videos", with: "")
            .replacingOccurrences(of: " Pictures", with: "")
            .replacingOccurrences(of: " Photos", with: "")
            
        let p = url.path.lowercased()
        let isHyperlapse = p.contains("hyperlapse") || p.contains("timelapse")
        let isPano = p.contains("panorama") || p.contains("pano")
        
        let ext = url.pathExtension.lowercased()
        let videoExts = ["mp4", "mov", "mxf", "mts", "m4v"]
        
        let isVideoCategory = isHyperlapse ? true : (isPano ? false : videoExts.contains(ext))
        
        if isVideoCategory {
            return "\(cleanBase) Videos"
        } else {
            return cleanBase == "Mini4Pro" ? "\(cleanBase) Pictures" : "\(cleanBase) Photos"
        }
    }

    func bucket(for url: URL) -> String {
        let base = baseBucket(for: url) ?? "Imported"
        return applyCategory(to: base, url: url)
    }
}
