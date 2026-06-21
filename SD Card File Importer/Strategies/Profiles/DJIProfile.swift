import Foundation

struct DJIProfile: CameraProfile {
    let id = "DJI"
    let fm = FileManager.default
    
    func match(url: URL) -> String? {
        let p = url.standardizedFileURL.path.lowercased()
        
        // Pocket 3 (using .LRF proxy as definitive marker)
        let proxyBase = url.deletingPathExtension()
        let hasPocket3Proxy = fm.fileExists(atPath: proxyBase.appendingPathExtension("LRF").path)
            || fm.fileExists(atPath: proxyBase.appendingPathExtension("lrf").path)

        if hasPocket3Proxy {
            return "Pocket3 Videos"
        }
        
        // Action 4 / Generic DJI (Default for dji_001 if no proxy found)
        if p.contains("/dcim/dji_001") {
            return "Action4 Videos"
        }
        
        // Mini 4 Pro / DJI Drones (100MEDIA or standalone Panorama/Hyperlapse folders)
        if p.contains("/dcim/100media") || p.contains("panorama") || p.contains("pano") || p.contains("hyperlapse") || p.contains("timelapse") {
            return "Mini4Pro Videos"
        }
        
        return nil
    }
}
