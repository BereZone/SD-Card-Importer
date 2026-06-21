import SwiftUI
import AppKit

/// A service responsible for managing macOS Security-Scoped Bookmarks.
/// This allows the app to retain access to external volumes and user-selected destination folders across app restarts.
class PermissionService {
    static let shared = PermissionService()
    
    // Security-scoped bookmarks for SD card roots the user granted
    @AppStorage("sourceBookmarksJSON") var sourceBookmarksJSON: Data?
    
    // Bookkeeping for scoped URLs by path
    var scopedURLForVolumePath: [String: URL] = [:]
    
    /// Restores security-scoped URLs for all previously granted SD card sources.
    /// - Returns: An array of successfully resolved and accessed `URL`s.
    func restoreSourceBookmarks() -> [URL] {
        var urls: [URL] = []
        scopedURLForVolumePath.removeAll()
        for d in loadSourceBookmarkDatas() {
            var stale = false
            if let u = try? URL(
                resolvingBookmarkData: d,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = u.startAccessingSecurityScopedResource()
                let path = u.standardizedFileURL.path
                if scopedURLForVolumePath[path] == nil {
                    scopedURLForVolumePath[path] = u
                    urls.append(u)
                }
            }
        }
        return urls
    }
    
    func loadSourceBookmarkDatas() -> [Data] {
        guard let data = sourceBookmarksJSON else { return [] }
        return (try? JSONDecoder().decode([Data].self, from: data)) ?? []
    }

    func saveSourceBookmarkDatas(_ arr: [Data]) {
        sourceBookmarksJSON = try? JSONEncoder().encode(arr)
    }
    
    func appendSourceBookmarks(for urls: [URL]) {
        var existingDatas = loadSourceBookmarkDatas()
        var existingPaths = Set<String>()

        for d in existingDatas {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) {
                existingPaths.insert(u.standardizedFileURL.path)
            }
        }

        for u in urls {
            let p = u.standardizedFileURL.path
            guard !existingPaths.contains(p) else { continue }
            if let d = try? u.bookmarkData(options: [.withSecurityScope],
                                         includingResourceValuesForKeys: nil,
                                         relativeTo: nil) {
                existingDatas.append(d)
                existingPaths.insert(p)
                scopedURLForVolumePath[p] = u
            }
        }
        saveSourceBookmarkDatas(existingDatas)
    }
    
    func removeVolumeBookmark(for url: URL, ignoredPaths: inout Set<String>) {
        let pathToRemove = url.standardizedFileURL.path
        
        ignoredPaths.insert(pathToRemove)
        
        let existingDatas = loadSourceBookmarkDatas()
        var newDatas: [Data] = []

        for d in existingDatas {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) {
                if u.standardizedFileURL.path == pathToRemove {
                    u.stopAccessingSecurityScopedResource()
                } else {
                    newDatas.append(d)
                }
            }
        }
        
        saveSourceBookmarkDatas(newDatas)
        scopedURLForVolumePath.removeValue(forKey: pathToRemove)
    }
    
    func storeDestinationBookmark(for url: URL) -> Data? {
        return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    
    func restoreDestinationBookmark(from data: Data) -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
            if url.startAccessingSecurityScopedResource() {
                return url
            }
        }
        return nil
    }
    
    /// Displays a native macOS file picker asking the user to explicitly grant read/write access to volumes.
    /// - Parameter volumes: A list of default volumes to point the panel to.
    /// - Returns: An array of URLs the user granted access to.
    @MainActor
    func promptForAccess(to volumes: [URL]) async -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Grant access to SD card"
        panel.directoryURL = volumes.first
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Grant Access"
        
        if panel.runModal() == .OK {
            for url in panel.urls { _ = url.startAccessingSecurityScopedResource() }
            return panel.urls
        }
        return []
    }
}
