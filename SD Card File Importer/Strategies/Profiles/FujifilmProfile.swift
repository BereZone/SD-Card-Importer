import Foundation

struct FujifilmProfile: CameraProfile {
    let id = "Fujifilm"
    
    func match(url: URL) -> String? {
        let p = url.standardizedFileURL.path.lowercased()
        let ext = url.pathExtension.lowercased()
        
        // Match Fuji extensions
        if ext == "raf" {
            return "Fujifilm Photos"
        }
        
        // Match Fuji folder structure (e.g. DCIM/100_FUJI)
        if p.contains("_fuji") {
            return "Fujifilm"
        }
        
        return nil
    }
}
