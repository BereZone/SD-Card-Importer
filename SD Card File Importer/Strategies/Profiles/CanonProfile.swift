import Foundation

struct CanonProfile: CameraProfile {
    let id = "Canon"
    
    func match(url: URL) -> String? {
        let p = url.standardizedFileURL.path.lowercased()
        let ext = url.pathExtension.lowercased()
        
        // Match Canon extensions
        if ext == "cr2" || ext == "cr3" {
            return "Canon Photos"
        }
        
        // Match Canon folder structure (e.g. DCIM/100CANON)
        if p.contains("canon") {
            // Let the Category manager determine if it's photos or videos based on extension
            return "Canon"
        }
        
        // Match older AVCHD video structure sometimes used by Canon
        // Note: Panasonic also uses AVCHD, but if "canon" didn't match and it's AVCHD, it might be ambiguous.
        // We'll leave it simple for now.
        if p.contains("/private/avchd") {
            return "AVCHD Camera"
        }
        
        return nil
    }
}
