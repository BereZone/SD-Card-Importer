import SwiftUI

/// Reading and writing the settings that outlive a launch: import options, the
/// per-card folder assignments, and the destination bookmark.
extension ImportViewModel {

    // MARK: - Options

    func loadOptions() {
        guard let data = importOptionsJSON,
              let decoded = try? JSONDecoder().decode(ImportOptions.self, from: data)
        else { return }
        options = decoded
    }

    func saveOptions() {
        importOptionsJSON = try? JSONEncoder().encode(options)
    }

    // MARK: - Folder assignments

    func loadCustomBuckets() {
        if let dataPhotos = customSourceBucketsPhotosJSON {
            customBucketsPhotos = (try? JSONDecoder()
                .decode([String: String].self, from: dataPhotos)) ?? [:]
        }
        if let dataVideos = customSourceBucketsVideosJSON {
            customBucketsVideos = (try? JSONDecoder()
                .decode([String: String].self, from: dataVideos)) ?? [:]
        }

        if let dropData = customDropdownBucketsJSON,
           let decoded = try? JSONDecoder().decode([String].self, from: dropData) {
            // "Auto-Detect" and "Custom..." used to be stored as list entries and
            // rendered as if they were folder names. They are picker affordances,
            // so the picker supplies them and they are filtered out of stored lists
            // written by earlier versions.
            dropdownBuckets = decoded.filter { $0 != "Auto-Detect" && $0 != "Custom..." }
        } else {
            // Generic starting points. The previous defaults were one person's
            // camera bag (Pocket3, Action4, A7C, Mini4Pro), which meant every new
            // user's first screen was full of hardware they do not own.
            dropdownBuckets = ["Camera", "Drone", "Action Cam", "Phone"]
        }
    }

    func saveCustomBuckets() {
        customSourceBucketsPhotosJSON = try? JSONEncoder().encode(customBucketsPhotos)
        customSourceBucketsVideosJSON = try? JSONEncoder().encode(customBucketsVideos)
    }

    func saveDropdownBuckets() {
        customDropdownBucketsJSON = try? JSONEncoder().encode(dropdownBuckets)
    }

    func setCustomPhotosBucket(for url: URL, bucket: String) {
        guard let path = DestinationPlanner.volumeRootPath(for: url) else { return }
        if bucket == "Auto-Detect" || bucket == "Custom..." {
            customBucketsPhotos.removeValue(forKey: path)
            log("Photos from \(url.lastPathComponent) will use the auto-detected camera folder.")
        } else {
            let clean = DestinationPlanner.sanitizeFolderName(bucket)
            guard !clean.isEmpty else { return }
            customBucketsPhotos[path] = clean
            log("Photos from \(url.lastPathComponent) will go to '\(clean)'.")
        }
        saveCustomBuckets()
    }

    func setCustomVideosBucket(for url: URL, bucket: String) {
        guard let path = DestinationPlanner.volumeRootPath(for: url) else { return }
        if bucket == "Auto-Detect" || bucket == "Custom..." {
            customBucketsVideos.removeValue(forKey: path)
            log("Videos from \(url.lastPathComponent) will use the auto-detected camera folder.")
        } else {
            let clean = DestinationPlanner.sanitizeFolderName(bucket)
            guard !clean.isEmpty else { return }
            customBucketsVideos[path] = clean
            log("Videos from \(url.lastPathComponent) will go to '\(clean)'.")
        }
        saveCustomBuckets()
    }

    // MARK: - Destination

    func storeDestinationBookmark() {
        guard let url = destinationURL else { destBookmarkData = nil; return }
        destBookmarkData = permissionService.storeDestinationBookmark(for: url)
    }
}
