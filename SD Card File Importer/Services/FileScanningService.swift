import Foundation

/// A service responsible for recursively scanning volumes for media files and identifying valid SD cards.
struct FileScanningService: Sendable {
    let fm = FileManager.default
    
    // Allowed extensions for all media
    let allowedExts: Set<String> = [
        "mp4", "mov", "mxf", "mts", "m4v", // Videos
        "arw", "jpg", "jpeg", "heic", "dng", "png" // Photos
    ]
    
    /// Determines if a mounted volume is likely a camera SD card by checking for standard directory structures.
    /// - Parameter vol: The root URL of the volume.
    /// - Returns: `true` if standard camera folders (like DCIM or PRIVATE) are found, `false` otherwise.
    func isCameraCard(_ vol: URL) -> Bool {
        let markers = [
            "DCIM",
            "DCIM/DJI_001",
            "DCIM/100MEDIA",
            "PRIVATE/M4ROOT",
            "PRIVATE/M4ROOT/CLIP",
            "PRIVATE/AVCHD",
            "PRIVATE/AVCHD/BDMV/STREAM",
            "MP_ROOT",
            "CLIP"
        ]
        for m in markers {
            if fm.fileExists(atPath: vol.appending(path: m).path) { return true }
        }
        return false
    }
    
    /// Scans a given volume for acceptable media files, utilizing known camera structures for efficiency.
    ///
    /// If the standard folders are not found or yield no files, the service falls back to a deep recursive scan.
    ///
    /// - Parameters:
    ///   - volume: The original URL of the volume.
    ///   - tokenizedURL: A security-scoped URL required by macOS sandboxing to access the external drive.
    ///   - debugScan: If `true`, logs hidden and excluded files.
    ///   - log: A closure for logging scanning progress.
    /// - Returns: An array of `ImportCandidate` objects representing discovered media files.
    func scanVolume(_ volume: URL, tokenizedURL: URL, debugScan: Bool, log: @Sendable (String) -> Void) -> [ImportCandidate] {
        var found: [ImportCandidate] = []
        
        let vol = tokenizedURL
        let had = vol.startAccessingSecurityScopedResource()
        defer { if had { vol.stopAccessingSecurityScopedResource() } }

        // Common camera roots
        let likelyRoots = [
            vol.appending(path: "PRIVATE/M4ROOT/CLIP"),
            vol.appending(path: "DCIM/DJI_001"),
            vol.appending(path: "DCIM/100MEDIA"),
            vol.appending(path: "DCIM"),
            vol.appending(path: "PRIVATE/AVCHD/BDMV/STREAM"),
            vol.appending(path: "MP_ROOT"),
            vol.appending(path: "CLIP"),
        ]

        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .fileSizeKey, .creationDateKey]
        var seenRoots = Set<URL>()
        var seenFiles = Set<String>()

        for root in likelyRoots {
            guard fm.fileExists(atPath: root.path) else { continue }
            
            if seenRoots.contains(root) { continue }
            seenRoots.insert(root)

            log("Scanning root: \(root.path)")
            let before = found.count

            if let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let item as URL in e {
                    if accept(url: item, keys: keys) {
                        let p = item.standardizedFileURL.path
                        if seenFiles.insert(p).inserted {
                             appendCandidate(url: item, into: &found)
                        } else if debugScan {
                             log("DBG skip duplicate: \(item.lastPathComponent)")
                        }
                    } else if debugScan {
                        log("DBG skip excluded: \(item.lastPathComponent)")
                    }
                }
            }
            
            // Fallback manual recursion
            if found.count == before {
                recursiveWalk(root, keys: keys) { item in
                    if accept(url: item, keys: keys) {
                        let p = item.standardizedFileURL.path
                        if seenFiles.insert(p).inserted {
                            appendCandidate(url: item, into: &found)
                        } else if debugScan {
                             log("DBG skip duplicate(rec): \(item.lastPathComponent)")
                        }
                    } else if debugScan {
                        log("DBG skip excluded(rec): \(item.lastPathComponent)")
                    }
                }
            }
            
            // DJI flat MP4s check
            if found.count == before,
               (root.lastPathComponent == "DJI_001" || root.lastPathComponent == "100MEDIA") {
                if let list = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for u in list where u.pathExtension.lowercased() == "mp4" {
                        let p = u.standardizedFileURL.path
                        if seenFiles.insert(p).inserted { appendCandidate(url: u, into: &found) }
                    }
                }
            }
            log("  +\(found.count - before) files in \(root.lastPathComponent)")
        } // End of likelyRoots loop
        
        // Universal Support / Root Fallback
        if found.isEmpty {
            log("No standard camera folders found. Scanning root recursively...")
            let before = found.count
            recursiveWalk(vol, keys: keys) { item in
                if accept(url: item, keys: keys) {
                    let p = item.standardizedFileURL.path
                    if seenFiles.insert(p).inserted {
                        appendCandidate(url: item, into: &found)
                    }
                }
            }
            log("  +\(found.count - before) files in root scan")
        }
        
        return found
    }
    
    private func recursiveWalk(_ dir: URL, keys: [URLResourceKey], visit: (URL) -> Void) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        for u in items {
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                recursiveWalk(u, keys: keys, visit: visit)
            } else {
                visit(u)
            }
        }
    }
    
    private func accept(url: URL, keys: [URLResourceKey]) -> Bool {
        if let vals = try? url.resourceValues(forKeys: Set(keys)) {
            if vals.isDirectory == true { return false }
            if vals.isHidden == true { return false }
        }
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".lrv") || name.hasSuffix(".lrf") || name.hasSuffix(".thm") || name.contains("_t") {
            return false
        }
        return allowedExts.contains(url.pathExtension.lowercased())
    }

    private func appendCandidate(url: URL, into arr: inout [ImportCandidate]) {
        let d = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { UInt64($0) } ?? 0
        arr.append(ImportCandidate(url: url, date: d, fileSize: size))
    }
    
    /// Identifies all currently mounted removable volumes that match the signature of a camera SD card.
    ///
    /// - Parameters:
    ///   - ignoring: A set of paths that the user has explicitly dismissed.
    ///   - destRoot: The current import destination root (which should be excluded from sources).
    /// - Returns: An array of URLs pointing to the root of discovered SD cards.
    func getMountedVolumes(ignoring: Set<String>, destRoot: URL?) -> [URL] {
         var results: [URL] = []
         if let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey],
                                              options: [.skipHiddenVolumes]) {
             for url in vols {
                 let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? false
                 guard !isInternal, isCameraCard(url) else { continue }
                 results.append(url)
             }
         }
         if let names = try? fm.contentsOfDirectory(atPath: "/Volumes") {
             for name in names where !name.isEmpty {
                 let u = URL(fileURLWithPath: "/Volumes/\(name)")
                 guard isCameraCard(u) else { continue }
                 results.append(u)
             }
         }
         results.removeAll { $0.standardizedFileURL.path == "/" }
         if let destRoot = destRoot {
             results.removeAll { $0.standardizedFileURL == destRoot.standardizedFileURL }
         }
         results.removeAll { ignoring.contains($0.standardizedFileURL.path) }
         return results
    }
}
