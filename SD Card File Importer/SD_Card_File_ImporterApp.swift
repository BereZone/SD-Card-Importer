import SwiftUI
import Combine
import AVFoundation
import AppKit

// MARK: - Model

struct ImportOptions {
    var dryRun: Bool = true
    var moveInsteadOfCopy: Bool = false
    var ejectAfterImport: Bool = false
}

struct ImportCandidate: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let fileSize: UInt64
}

// NEW: Possible bucket names for the dropdown
let predefinedBuckets = [
    "Auto-Detect",
    "Pocket3 Videos",
    "Action4 Videos",
    "A7C Videos",
    "A7C Photos",
    "Mini4Pro Videos",
    "Phone Videos",
    "Custom..."
]

// MARK: - Import Manager

final class ImportManager: ObservableObject {
    // UI state
    @Published var removableVolumes: [URL] = []
    @Published var candidates: [ImportCandidate] = []
    @Published var logLines: [String] = []
    @Published var isImporting: Bool = false
    @Published var progress: Double = 0
    @Published var debugScan: Bool = false

    // Destination bookmark (where files are imported to)
    @AppStorage("destBookmarkData") var destBookmarkData: Data?
    @Published var destinationURL: URL? = nil {
        didSet {
            // Only store if not nil to avoid endless loops or crashes
            if destinationURL != nil {
                storeBookmark(for: destinationURL)
            }
        }
    }

    // Security-scoped bookmarks for SD card roots the user granted
    @AppStorage("sourceBookmarksJSON") var sourceBookmarksJSON: Data?

    // NEW: User-defined bucket for a source path, keyed by path String
    @AppStorage("customSourceBucketsJSON") var customSourceBucketsJSON: Data?
    @Published var customBuckets: [String: String] = [:]

    // File & scan helpers
    let fm = FileManager.default
    
    // UPDATED: Allowed extensions for all media
    let allowedExts: Set<String> = [
        "mp4", "mov", "mxf", "mts", "m4v", // Videos
        "arw", "jpg", "jpeg", "heic", "dng", "png" // Photos
    ]

    // Month labels
    let englishMonthFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    // Optional: map specific volume names to bucket names
    let volumeBucketOverride: [String: String] = [:]

    // Bookkeeping for scoped URLs by path
    var scopedURLForVolumePath: [String: URL] = [:]
    var didAutoPromptThisRun = false
    var observers: [NSObjectProtocol] = []

    // A session-only set of paths to ignore
    @Published var sessionIgnoredPaths = Set<String>()

    init() {
        loadCustomBuckets()
        observeMounts()
    }
    
    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }
    
    // MARK: - Custom Bucket Storage
    
    func loadCustomBuckets() {
        guard let data = customSourceBucketsJSON else { return }
        customBuckets = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func saveCustomBuckets() {
        customSourceBucketsJSON = try? JSONEncoder().encode(customBuckets)
    }

    // Removed 'private' - Accessible to View
    func getVolumeRootPath(for url: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        // Typical removable volume path: /Volumes/VOLUME_NAME/...
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else {
            // If it's not a /Volumes mount, return the root of the file system
            return url.standardizedFileURL.deletingLastPathComponent().path
        }
        
        // Reconstruct the root path: /Volumes/VOLUME_NAME
        let rootPath = "/\(components[1])/\(components[2])"
        return rootPath
    }

    func setCustomBucket(for url: URL, bucket: String) {
        guard let path = getVolumeRootPath(for: url) else { return }
        
        // Ensure "Custom..." placeholder isn't saved as the actual folder name
        if bucket == "Auto-Detect" || bucket == "Custom..." {
            customBuckets.removeValue(forKey: path)
        } else {
            customBuckets[path] = bucket
        }
        saveCustomBuckets()
        log("Set custom bucket for \(url.lastPathComponent) to '\(bucket)'")
    }

    // MARK: - Source bookmark storage

    func loadSourceBookmarkDatas() -> [Data] {
        guard let data = sourceBookmarksJSON else { return [] }
        return (try? JSONDecoder().decode([Data].self, from: data)) ?? []
    }

    func saveSourceBookmarkDatas(_ arr: [Data]) {
        sourceBookmarksJSON = try? JSONEncoder().encode(arr)
    }
    
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

    func removeVolumeFromList(for url: URL) {
        let pathToRemove = url.standardizedFileURL.path
        log("Attempting to remove '\(url.lastPathComponent)' from list.")

        // 1. Add to session ignore list
        sessionIgnoredPaths.insert(pathToRemove)
        
        // 2. Remove any custom bucket setting for this path
        if let root = getVolumeRootPath(for: url) {
             customBuckets.removeValue(forKey: root)
             saveCustomBuckets()
        }

        // 3. Check if it was also a bookmark. If so, remove the bookmark permanently.
        let existingDatas = loadSourceBookmarkDatas()
        var newDatas: [Data] = []
        var didRemoveBookmark = false

        for d in existingDatas {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) {
                if u.standardizedFileURL.path == pathToRemove {
                    u.stopAccessingSecurityScopedResource()
                    didRemoveBookmark = true
                    log("...it was a bookmark. Permanently removing.")
                } else {
                    newDatas.append(d)
                }
            }
        }

        if didRemoveBookmark {
            saveSourceBookmarkDatas(newDatas)
            scopedURLForVolumePath.removeValue(forKey: pathToRemove)
        } else {
            log("...it was not a bookmark. Ignoring for this session.")
        }
        
        refreshVolumes(autoPrompt: false)
    }
    
    // MARK: - Volume observation

    func observeMounts() {
        let nc = NSWorkspace.shared.notificationCenter
        let didMount = nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log("Volume mounted")
            self?.refreshVolumes(autoPrompt: true)
        }
        let didUnmount = nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log("Volume unmounted")
            self?.refreshVolumes()
        }
        observers = [didMount, didUnmount]
    }

    // MARK: - Volume discovery

    func refreshVolumes(autoPrompt: Bool = false) {
        log("Refreshing volumes…")
        DispatchQueue.main.async { self.candidates = [] }
        
        var results: [URL] = []
        results.append(contentsOf: restoreSourceBookmarks())

        if let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey],
                                             options: [.skipHiddenVolumes]) {
            for url in vols {
                let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? false
                // isCameraCard accessible here
                guard !isInternal, isCameraCard(url) else { continue }
                results.append(url)
            }
        }

        if let names = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            for name in names where !name.isEmpty {
                let u = URL(fileURLWithPath: "/Volumes/\(name)")
                // isCameraCard accessible here
                guard isCameraCard(u) else { continue }
                results.append(u)
            }
        }
        results.removeAll { $0.standardizedFileURL.path == "/" }
        
        // destinationVolumeRoot accessible here
        if let destRoot = destinationVolumeRoot() {
            results.removeAll { $0.standardizedFileURL == destRoot.standardizedFileURL }
        }

        results.removeAll { sessionIgnoredPaths.contains($0.standardizedFileURL.path) }

        var byPath: [String: URL] = [:]
        for u in results {
            let path = u.standardizedFileURL.path
            if let scoped = scopedURLForVolumePath[path] {
                byPath[path] = scoped
            } else if byPath[path] == nil {
                byPath[path] = u
            }
        }
        removableVolumes = byPath.values.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let labels = removableVolumes.map { u in
            let p = u.standardizedFileURL.path
            return scopedURLForVolumePath[p] != nil ? "\(u.lastPathComponent) (scoped)" : "\(u.lastPathComponent)"
        }
        log("Detected camera cards: \(labels)")

        if autoPrompt, !didAutoPromptThisRun {
            let unscoped = removableVolumes.filter { scopedURLForVolumePath[$0.standardizedFileURL.path] == nil }
            if !unscoped.isEmpty {
                didAutoPromptThisRun = true
                promptForAccess(to: unscoped)
            }
        }
    }

    // Removed 'private' - Accessible to View
    func promptForAccess(to volumes: [URL]) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "Grant access to SD card"
            panel.directoryURL = volumes.first
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = true
            panel.prompt = "Grant Access"
            if panel.runModal() == .OK {
                for url in panel.urls { _ = url.startAccessingSecurityScopedResource() }
                self.appendSourceBookmarks(for: panel.urls)
                
                for u in panel.urls {
                    self.sessionIgnoredPaths.remove(u.standardizedFileURL.path)
                }
                
                self.refreshVolumes()
                self.log("Granted access for: \(panel.urls.map(\.lastPathComponent))")
            } else {
                self.log("Access not granted; scanning will show 0 files.")
            }
        }
    }

    // Removed 'private' - Accessible to View and Refresh logic
    func isCameraCard(_ vol: URL) -> Bool {
        let markers = [
            "DCIM",
            "DCIM/DJI_001",           // DJI Pocket / DJI cameras
            "DCIM/100MEDIA",          // DJI alt
            "PRIVATE/M4ROOT",
            "PRIVATE/M4ROOT/CLIP",    // Sony XAVC S/HS
            "PRIVATE/AVCHD",
            "PRIVATE/AVCHD/BDMV/STREAM", // AVCHD MTS
            "MP_ROOT",
            "CLIP"                    // some MXF cards
        ]
        for m in markers {
            if fm.fileExists(atPath: vol.appending(path: m).path) { return true }
        }
        return false
    }

    // Removed 'private' - Accessible to View
    func destinationVolumeRoot() -> URL? {
        guard let dest = destinationURL?.standardizedFileURL else { return nil }
        let c = dest.pathComponents
        guard c.count > 2, c[0] == "/", c[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/\(c[2])")
    }

    // MARK: - Destination bookmark

    // Removed 'private' - Accessible to View
    func restoreBookmark() {
        guard let data = destBookmarkData else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) {
            if url.startAccessingSecurityScopedResource() {
                destinationURL = url
                if stale { storeBookmark(for: url) }
            }
        }
    }

    // Removed 'private' - Accessible to didSet
    func storeBookmark(for url: URL?) {
        guard let url else { destBookmarkData = nil; return }
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                         includingResourceValuesForKeys: nil,
                                         relativeTo: nil) {
            destBookmarkData = data
        }
    }

    // MARK: - UI actions

    // Removed 'private' - Accessible to View
    func pickDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Import Destination"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            destinationURL = url
        }
    }

    // Removed 'private' - Accessible to View
    func addSourceVolume() {
        let panel = NSOpenPanel()
        panel.title = "Grant access to SD card"
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { _ = url.startAccessingSecurityScopedResource() }
            self.appendSourceBookmarks(for: panel.urls)
            
            for u in panel.urls {
                self.sessionIgnoredPaths.remove(u.standardizedFileURL.path)
            }
            
            self.refreshVolumes()
            self.log("Granted access for: \(panel.urls.map(\.lastPathComponent))")
        }
    }

    func clearIgnoresAndRefresh(autoPrompt: Bool = true) {
        log("Clearing ignore list and refreshing...")
        sessionIgnoredPaths.removeAll()
        refreshVolumes(autoPrompt: autoPrompt)
    }

    // MARK: - Scan

    func scanForCandidates() {
        log("Scanning volumes…")
        candidates = []
        progress = 0
        let vols = removableVolumes
        let totalVols = max(vols.count, 1)
        for (i, vol) in vols.enumerated() {
            log("• \(vol.path)")
            candidates.append(contentsOf: scanVolume(vol))
            progress = Double(i + 1) / Double(totalVols)
        }
        log("Found \(candidates.count) files.")
    }

    private func tokenizedURL(for volume: URL) -> URL {
        scopedURLForVolumePath[volume.standardizedFileURL.path] ?? volume
    }

    private func scanVolume(_ volume: URL) -> [ImportCandidate] {
        var found: [ImportCandidate] = []

        let vol = tokenizedURL(for: volume)
        let had = vol.startAccessingSecurityScopedResource()
        defer { if had { vol.stopAccessingSecurityScopedResource() } }

        // Common camera roots - ORDER MATTERS for de-duplication
        let likelyRoots = [
            vol.appending(path: "PRIVATE/M4ROOT/CLIP"), // Sony Video (most specific)
            vol.appending(path: "DCIM/DJI_001"),        // DJI standard video
            vol.appending(path: "DCIM/100MEDIA"),       // DJI alt video
            vol.appending(path: "DCIM"),                // Generic DCIM (Photos & general fallback)
            vol.appending(path: "PRIVATE/AVCHD/BDMV/STREAM"),
            vol.appending(path: "MP_ROOT"),
            vol.appending(path: "CLIP"),
        ]

        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .fileSizeKey, .creationDateKey]
        var seenRoots = Set<URL>()
        
        // Tracks standardized file path to prevent duplicates
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
                        // Check if file path is already seen before appending
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

            // Fallback manual recursion if enumerator misses anything
            if found.count == before {
                recursiveWalk(root, keys: keys) { item in
                    if accept(url: item, keys: keys) {
                        let p = item.standardizedFileURL.path
                        // Check if file path is already seen before appending
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

            // DJI flat MP4s directly in DJI_001 or 100MEDIA
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
        
        // Exclude common proxy/thumbnail markers
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

    // MARK: - Import

    func importAll(options: ImportOptions) async {
        guard let destRoot = destinationURL else {
            log("❗️ Pick a destination first.")
            return
        }

        isImporting = true
        defer { isImporting = false }

        let total = max(candidates.count, 1)
        var imported = 0

        for (idx, c) in candidates.enumerated() {
            progress = Double(idx) / Double(total)
            let destURL = buildDestination(for: c, root: destRoot)

            // Skip if duplicate already there
            if fm.fileExists(atPath: destURL.path) {
                log("⤵︎ Skipping existing: \(destURL.lastPathComponent)")
                continue
            }

            if options.dryRun {
                // 100% non-mutating: don’t create any folders on Dry Run
                log("DRY RUN: Would create \(destURL.deletingLastPathComponent().path)")
                log("DRY RUN: Would \(options.moveInsteadOfCopy ? "move" : "copy") → \(destURL.path)")
                continue
            }

            do {
                // Create folders only when actually importing
                try fm.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if options.moveInsteadOfCopy {
                    try fm.moveItem(at: c.url, to: destURL)   // removes only the SOURCE (SD card) on success
                } else {
                    try copyFile(from: c.url, to: destURL)    // never overwrites destination
                }
                log("✅ Imported: \(destURL.lastPathComponent)")
                imported += 1
            } catch {
                log("❌ Error importing \(c.url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        progress = 1
        log("Done. Imported \(imported)/\(candidates.count).")

        if options.ejectAfterImport && !options.dryRun {
            ejectRemovableVolumes()
        }
    }


    // MARK: - Destination path rules
    // Build: <Bucket>/<YYYY>/<MM_Month>/<DD>/<filename>

    private func cameraBucket(for c: ImportCandidate) -> String {
        let sourcePath = c.url.standardizedFileURL.path
        
        // --- 1. USER'S CUSTOM CHOICE (Highest Priority) ---
        if let volumeRootPath = getVolumeRootPath(for: c.url),
           let customBucket = customBuckets[volumeRootPath] {
             
            return customBucket
        }
        
        // 2) Volume-name override (most reliable if you set it)
        if let volName = c.url.pathComponents.dropFirst(2).first, // "/Volumes/<Name>/…"
           let mapped = volumeBucketOverride[volName] {
            return mapped
        }

        // 3) Path heuristics / filename patterns (Fallback)
        let p = c.url.standardizedFileURL.path.lowercased()
        
        // --- SONY PHOTO DETECTION ---
        // If it's an ARW, or inside a folder like "100MSDCF", it's a Sony Photo.
        if c.url.pathExtension.lowercased() == "arw" || p.contains("msdcf") {
             return "A7C Photos"
        }
        
        // Pocket 3 (using .LRF proxy as definitive marker)
        let proxyBase = c.url.deletingPathExtension()
        let hasPocket3Proxy = fm.fileExists(atPath: proxyBase.appendingPathExtension("LRF").path)
            || fm.fileExists(atPath: proxyBase.appendingPathExtension("lrf").path)

        if hasPocket3Proxy {
            return "Pocket3 Videos"
        }
        
        // Action 4 / Generic DJI (Default for dji_001 if no proxy found)
        if p.contains("/dcim/dji_001") {
            return "Action4 Videos"
        }

        // Sony A7C / XAVC S/HS
        if p.contains("/private/m4root/clip") {
            return "A7C Videos"
        }

        // DJI drones / action (100MEDIA)
        if p.contains("/dcim/100media") {
            return "Drone Videos"
        }

        return "Imported Videos" // fallback bucket
    }

    // Build: <Bucket>/<YYYY>/<MM_Month>/<DD>/<filename>
    private func buildDestination(for c: ImportCandidate, root: URL) -> URL {
        let cal = Calendar(identifier: .gregorian)
        let y  = cal.component(.year,  from: c.date)
        let m  = cal.component(.month, from: c.date)
        let d  = cal.component(.day,   from: c.date)

        let monthName   = englishMonthFormatter.monthSymbols[m - 1]
        let monthFolder = String(format: "%02d_%@", m, monthName) // "10_October"
        let dayFolder   = String(format: "%02d", d)              // "28"

        let bucket = cameraBucket(for: c)

        // Build desired segments in order
        let desired = [bucket, "\(y)", monthFolder, dayFolder]

        // Normalize root path components for case-insensitive comparison
        var url = root.standardizedFileURL
        let existing = Set(url.pathComponents.map { $0.lowercased() })

        for seg in desired {
            if !existing.contains(seg.lowercased()) {
                url.append(path: seg)
            }
        }
        return url.appending(path: c.url.lastPathComponent)
    }

    // MARK: - File ops

    private func copyFile(from src: URL, to dst: URL) throws {
        let inHandle = try FileHandle(forReadingFrom: src); defer { try? inHandle.close() }
        fm.createFile(atPath: dst.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: dst); defer { try? outHandle.close() }
        while true {
            let chunk = try? inHandle.read(upToCount: 1024 * 1024) // 1 MB
            if let chunk, !chunk.isEmpty { try? outHandle.write(contentsOf: chunk) } else { break }
        }
        if let attrs = try? fm.attributesOfItem(atPath: src.path) {
            try? fm.setAttributes(attrs, ofItemAtPath: dst.path)
        }
    }

    private func ejectRemovableVolumes() {
        for vol in removableVolumes {
            FileManager.default.unmountVolume(
                at: tokenizedURL(for: vol),
                options: [.withoutUI, .allPartitionsAndEjectDisk],
                completionHandler: { error in
                    if let error {
                        self.log("⚠️ Eject failed (\(vol.lastPathComponent)): \(error.localizedDescription)")
                    } else {
                        self.log("🔌 Ejected: \(vol.lastPathComponent)")
                    }
                }
            )
        }
    }

    // MARK: - Logging

    private func log(_ s: String) {
        DispatchQueue.main.async { self.logLines.append(s) }
        print(s)
    }
}

// MARK: - UI

struct ImporterView: View {
    @StateObject private var mgr = ImportManager()
    @State private var options = ImportOptions()
    
    // State to track the custom folder name input for the current volume
    @State private var tempCustomBucketName: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Destination
            GroupBox("Destination") {
                HStack {
                    Text(mgr.destinationURL?.path(percentEncoded: false) ?? "(not set)")
                        .font(.system(.body, design: .rounded))
                        .lineLimit(2)
                    Spacer()
                    Button("Choose…") { mgr.pickDestination() }
                }
            }

            // Sources
            GroupBox("Detected SD Cards") {
                HStack(spacing: 12) {
                    Button { mgr.clearIgnoresAndRefresh(autoPrompt: true) } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        mgr.addSourceVolume()
                    } label: {
                        Label("Add SD Card…", systemImage: "plus")
                    }
                    Toggle("Debug scan", isOn: $mgr.debugScan).toggleStyle(.switch)
                    Spacer()
                }

                if mgr.removableVolumes.isEmpty {
                    Text("No removable volumes found.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(mgr.removableVolumes, id: \.self) { url in
                            let volumeKey = mgr.getVolumeRootPath(for: url) ?? ""
                            let currentSavedBucket = mgr.customBuckets[volumeKey] ?? "Auto-Detect"
                            
                            // Determine if the saved bucket is a custom string (not in the predefined list)
                            let isCustomSaved = !predefinedBuckets.contains(currentSavedBucket) && currentSavedBucket != "Auto-Detect"
                            
                            // Determine if the picker is currently showing the "Custom..." option
                            let isPickerCustom = (currentSavedBucket == "Custom..." || isCustomSaved)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "externaldrive")
                                    Text(url.lastPathComponent)
                                    Text(url.path)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Spacer()
                                    
                                    // Custom Bucket Picker
                                    Picker("Import Bucket", selection: Binding(
                                        get: {
                                            if isCustomSaved {
                                                // If we have a saved custom name, we ensure the local temp state matches it
                                                // so the text field isn't empty if they switch back to "Custom..."
                                                if self.tempCustomBucketName[volumeKey] == nil {
                                                    DispatchQueue.main.async {
                                                        self.tempCustomBucketName[volumeKey] = currentSavedBucket
                                                    }
                                                }
                                                return "Custom..."
                                            }
                                            return currentSavedBucket
                                        },
                                        set: { selectedBucket in
                                            if selectedBucket != "Custom..." {
                                                // Standard selection: save it directly and clear the custom input state
                                                mgr.setCustomBucket(for: url, bucket: selectedBucket)
                                                self.tempCustomBucketName.removeValue(forKey: volumeKey)
                                            } else {
                                                // Selected "Custom...": initialize TextField state
                                                let initialName = self.tempCustomBucketName[volumeKey] ?? currentSavedBucket
                                                let newCustomName = isCustomSaved ? initialName : "Custom Project"
                                                
                                                self.tempCustomBucketName[volumeKey] = newCustomName
                                                
                                                // We only save "Custom..." as a marker if the temp name isn't ready,
                                                // or we leave it pending user input.
                                                if newCustomName == "Custom Project" {
                                                     mgr.setCustomBucket(for: url, bucket: newCustomName)
                                                }
                                            }
                                        }
                                    )) {
                                        ForEach(predefinedBuckets, id: \.self) { bucketName in
                                            Text(bucketName).tag(bucketName)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 150)
                                    
                                    // Remove Button
                                    Button(role: .destructive) {
                                        mgr.removeVolumeFromList(for: url)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .contentShape(Rectangle())
                                }
                                
                                // Conditional TextField for Custom Folder Name
                                if isPickerCustom {
                                    HStack {
                                        Text("Folder:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        TextField("Enter custom folder name", text: Binding(
                                            get: {
                                                // Use temp state if available, otherwise fallback to saved state
                                                return self.tempCustomBucketName[volumeKey] ?? (isCustomSaved ? currentSavedBucket : "Custom Project")
                                            },
                                            set: { newValue in
                                                // Update ONLY the local temp state on keystroke
                                                self.tempCustomBucketName[volumeKey] = newValue
                                            }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit {
                                            // Commit to manager only on Return/Focus Loss
                                            if let newBucket = self.tempCustomBucketName[volumeKey], !newBucket.isEmpty {
                                                mgr.setCustomBucket(for: url, bucket: newBucket)
                                            } else {
                                                mgr.setCustomBucket(for: url, bucket: "Custom Project")
                                                self.tempCustomBucketName[volumeKey] = "Custom Project"
                                            }
                                        }
                                        .frame(maxWidth: 300)
                                    }
                                    .padding(.leading, 20)
                                } else if isCustomSaved {
                                    Text("Saved Custom Folder: \(currentSavedBucket)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 20)
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
            
            // Options
            GroupBox("Options") {
                Toggle("Dry run (don’t actually copy/move)", isOn: $options.dryRun)
                Toggle("Move instead of copy (DANGEROUS — use after verifying)", isOn: $options.moveInsteadOfCopy)
                Toggle("Eject cards after import", isOn: $options.ejectAfterImport)
            }

            // Actions
            HStack(spacing: 12) {
                Button { mgr.scanForCandidates() } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                Button {
                    Task { await mgr.importAll(options: options) }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(mgr.destinationURL == nil || mgr.isImporting)

                Spacer()
                ProgressView(value: mgr.progress).frame(width: 200)
            }

            // Results
            GroupBox("Found Files: \(mgr.candidates.count)") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(mgr.candidates) { c in
                            HStack(spacing: 8) {
                                Image(systemName: "film")
                                Text(c.url.lastPathComponent)
                                Spacer()
                                Text(byteCount(c.fileSize))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 220)
            }

            // Log
            GroupBox("Log") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(Array(mgr.logLines.enumerated()), id: \.offset) { i, line in
                                Text(line).font(.caption).monospaced().id(i)
                            }
                        }
                    }
                    .onChange(of: mgr.logLines) { _ in
                        withAnimation { proxy.scrollTo(max(0, mgr.logLines.count - 1)) }
                    }
                    .frame(minHeight: 120)
                }
            }
        }
        .padding(16)
        .onAppear {
            mgr.restoreBookmark()
            mgr.refreshVolumes(autoPrompt: true)
        }
        .frame(minWidth: 860, minHeight: 680)
    }

    private func byteCount(_ n: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }
}

@main
struct VideoImporterApp: App {
    var body: some Scene {
        WindowGroup {
            ImporterView()
        }
        .windowStyle(.titleBar)
    }
}
