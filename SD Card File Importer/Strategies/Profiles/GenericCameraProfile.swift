import Foundation

struct GenericCameraProfile: CameraProfile {
    let id = "GenericCamera"
    
    func match(url: URL) -> String? {
        let p = url.standardizedFileURL.path.lowercased()
        let ext = url.pathExtension.lowercased()
        
        // Match generic RAW extensions
        if ext == "dng" {
            return "Camera Photos"
        }
        
        // Match standard DCIM structure
        if p.contains("/dcim/") {
            return "Camera"
        }
        
        return nil
    }
}
