import Foundation

struct NikonProfile: CameraProfile {
    let id = "Nikon"
    
    func match(url: URL) -> String? {
        let p = url.standardizedFileURL.path.lowercased()
        let ext = url.pathExtension.lowercased()
        
        // Match Nikon extensions
        if ext == "nef" || ext == "nrw" {
            return "Nikon Photos"
        }
        
        // Match Nikon folder structure (e.g. DCIM/100ND850)
        // Nikon usually uses 'nd' followed by model number
        if p.range(of: "/dcim/\\d{3}nd", options: .regularExpression) != nil {
            return "Nikon"
        }
        
        return nil
    }
}
