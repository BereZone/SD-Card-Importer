import Foundation

struct PanasonicProfile: CameraProfile {
    let id = "Panasonic"
    
    func match(url: URL) -> String? {
        let p = url.standardizedFileURL.path.lowercased()
        let ext = url.pathExtension.lowercased()
        
        // Match Panasonic extensions
        if ext == "rw2" {
            return "Panasonic Photos"
        }
        
        // Match Panasonic folder structure (e.g. DCIM/100_PANA)
        if p.contains("_pana") || p.contains("/private/pana") {
            return "Panasonic"
        }
        
        return nil
    }
}
