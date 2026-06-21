import Foundation

struct SonyProfile: CameraProfile {
    let id = "Sony"
    
    func match(url: URL) -> String? {
        let p = url.standardizedFileURL.path.lowercased()
        
        // Sony A7C / XAVC S/HS Videos
        if p.contains("/private/m4root/clip") {
            return "A7C Videos"
        }
        
        // Sony Photos
        // If it's an ARW, or inside a folder like "100MSDCF", it's a Sony Photo.
        if url.pathExtension.lowercased() == "arw" || p.contains("msdcf") {
             return "A7C Photos"
        }
        
        return nil
    }
}
