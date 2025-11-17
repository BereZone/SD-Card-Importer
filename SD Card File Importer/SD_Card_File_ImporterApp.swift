// Video File Importer
// v1 features:
//  • Detects mounted camera cards
//  • Lets you grant access to SD cards
//  • Scans typical camera layouts (DJI DCIM/DJI_001, Sony M4ROOT/CLIP, AVCHD, etc.)
//  • Copies or moves files to a destination using folder scheme:
//      <Bucket>/<YYYY>/<MM_Month>/<DD>/<filename>
//  • Dry Run option, optional auto-eject, simple duplicate skip
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
    @AppStorage("destBookmarkData") private var destBookmarkData: Data?
    @Published var destinationURL: URL? = nil {
        didSet { storeBookmark(for: destinationURL) }
    }

    // Security-scoped bookmarks for SD card roots the user granted
    @AppStorage("sourceBookmarksJSON") private var sourceBookmarksJSON: Data?

    // File & scan helpers
    private let fm = FileManager.default
    private let videoExts: Set<String> = ["mp4", "mov", "mxf", "mts", "m4v"]

    // Month labels (stable English names regardless of system locale)
    private let englishMonthFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    // Optional: map specific volume names to bucket names (edit to taste)
    // Example: if your Pocket 3 card always mounts as “SD_Card”, map it here.
    private let volumeBucketOverride: [String: String] = [:
        // "SD_Card": "Pocket3 Videos",
        // "DJI_DRONE": "Mini4Pro Videos",
        // "SONY_SD": "A7C Videos",
    ]

    // Bookkeeping for scoped URLs by path
    private var scopedURLForVolumePath: [String: URL] = [:]
    private var didAutoPromptThisRun = false
    private var observers: [NSObjectProtocol] = []

    // A session-only set of paths to ignore
    private var sessionIgnoredPaths = Set<String>()

    init() { observeMounts() }
    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }

    // MARK: - Source bookmark storage

    private func loadSourceBookmarkDatas() -> [Data] {
        guard let data = sourceBookmarksJSON else { return [] }
        return (try? JSONDecoder().decode([Data].self, from: data)) ?? []
    }

    private func saveSourceBookmarkDatas(_ arr: [Data]) {
        sourceBookmarksJSON = try? JSONEncoder().encode(arr)
    }

    private func restoreSourceBookmarks() -> [URL] {
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

    private func appendSourceBookmarks(for urls: [URL]) {
        // de-dupe by path before saving
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
        //    This will prevent it from being re-discovered by refreshVolumes()
        sessionIgnoredPaths.insert(pathToRemove)

        // 2. Check if it was also a bookmark. If so, remove the bookmark permanently.
        let existingDatas = loadSourceBookmarkDatas()
        var newDatas: [Data] = []
        var didRemoveBookmark = false

        for d in existingDatas {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) {
                if u.standardizedFileURL.path == pathToRemove {
                    // This is the one to remove. Stop accessing and don't add to newDatas.
                    u.stopAccessingSecurityScopedResource()
                    didRemoveBookmark = true
                    log("...it was a bookmark. Permanently removing.")
                } else {
                    newDatas.append(d) // Keep this one
                }
            }
        }

        if didRemoveBookmark {
            saveSourceBookmarkDatas(newDatas)
            scopedURLForVolumePath.removeValue(forKey: pathToRemove)
        } else {
            log("...it was not a bookmark. Ignoring for this session.")
        }
        
        // 3. Refresh the UI list (which will now respect the sessionIgnoredPaths)
        refreshVolumes(autoPrompt: false) // No need to auto-prompt after an explicit removal
    }
    
    // MARK: - Volume observation

    private func observeMounts() {
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
        var results: [URL] = []

        // Include previously granted sources first (scoped)
        results.append(contentsOf: restoreSourceBookmarks())

        // System-reported volumes (skip hidden); only keep removable camera-like
        if let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey],
                                            options: [.skipHiddenVolumes]) {
            for url in vols {
                let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? false
                guard !isInternal, isCameraCard(url) else { continue }
                results.append(url)
            }
        }

        // Fallback: /Volumes pass
        if let names = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            for name in names where !name.isEmpty {
                let u = URL(fileURLWithPath: "/Volumes/\(name)")
                guard isCameraCard(u) else { continue }
                results.append(u)
            }
        }
        results.removeAll { $0.standardizedFileURL.path == "/" }
        
        // Don’t include the destination volume (avoid scanning your import SSD)
        if let destRoot = destinationVolumeRoot() {
            results.removeAll { $0.standardizedFileURL == destRoot.standardizedFileURL }
        }

        // Filter out session-ignored paths
        results.removeAll { sessionIgnoredPaths.contains($0.standardizedFileURL.path) }

        // De-dup by path; prefer scoped URL if available
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

        // If we found unscoped camera cards, prompt once this run to grant access
        if autoPrompt, !didAutoPromptThisRun {
            let unscoped = removableVolumes.filter { scopedURLForVolumePath[$0.standardizedFileURL.path] == nil }
            if !unscoped.isEmpty {
                didAutoPromptThisRun = true
                promptForAccess(to: unscoped)
            }
        }
    }

    private func promptForAccess(to volumes: [URL]) {
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
                self.refreshVolumes()
                self.log("Granted access for: \(panel.urls.map(\.lastPathComponent))")
            } else {
                self.log("Access not granted; scanning will show 0 files.")
            }
        }
    }

    /// Heuristics: treat a volume as a camera card if it contains typical camera markers.
    private func isCameraCard(_ vol: URL) -> Bool {
        let markers = [
            "DCIM",
            "DCIM/DJI_001",                   // DJI Pocket / DJI cameras
            "DCIM/100MEDIA",                  // DJI alt
            "PRIVATE/M4ROOT",
            "PRIVATE/M4ROOT/CLIP",            // Sony XAVC S/HS
            "PRIVATE/AVCHD",
            "PRIVATE/AVCHD/BDMV/STREAM",      // AVCHD MTS
            "MP_ROOT",
            "CLIP"                            // some MXF cards
        ]
        for m in markers {
            if fm.fileExists(atPath: vol.appending(path: m).path) { return true }
        }
        return false
    }

    /// If destination is on /Volumes/<Name>/..., return the root of that volume
    private func destinationVolumeRoot() -> URL? {
        guard let dest = destinationURL?.standardizedFileURL else { return nil }
        let c = dest.pathComponents
        guard c.count > 2, c[0] == "/", c[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/\(c[2])")
    }

    // MARK: - Destination bookmark

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

    private func storeBookmark(for url: URL?) {
        guard let url else { destBookmarkData = nil; return }
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil) {
            destBookmarkData = data
        }
    }

    // MARK: - UI actions

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

    func addSourceVolume() {
        let panel = NSOpenPanel()
        panel.title = "Grant access to SD card"
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { _ = url.startAccessingSecurityScopedResource() }
            appendSourceBookmarks(for: panel.urls)
            refreshVolumes()
            log("Added sources: \(panel.urls.map(\.lastPathComponent))")
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
        log("Found \(candidates.count) video files.")
    }

    private func tokenizedURL(for volume: URL) -> URL {
        scopedURLForVolumePath[volume.standardizedFileURL.path] ?? volume
    }

    private func scanVolume(_ volume: URL) -> [ImportCandidate] {
        var found: [ImportCandidate] = []

        let vol = tokenizedURL(for: volume)
        let had = vol.startAccessingSecurityScopedResource()
        defer { if had { vol.stopAccessingSecurityScopedResource() } }

        // Common camera roots
        let likelyRoots = [
            vol.appending(path: "DCIM/DJI_001"),           // DJI
            vol.appending(path: "DCIM/100MEDIA"),          // DJI alt
            vol.appending(path: "DCIM"),                   // generic DCIM
            vol.appending(path: "PRIVATE/M4ROOT/CLIP"),    // Sony XAVC
            vol.appending(path: "PRIVATE/AVCHD/BDMV/STREAM"), // AVCHD
            vol.appending(path: "MP_ROOT"),                // older Sony/others
            vol.appending(path: "CLIP"),                   // MXF
            vol                                            // fallback
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
                        if seenFiles.insert(p).inserted { appendCandidate(url: item, into: &found) }
                    } else if debugScan {
                        log("DBG skip: \(item.lastPathComponent)")
                    }
                }
            }

            // Fallback manual recursion if enumerator misses anything
            if found.count == before {
                recursiveWalk(root, keys: keys) { item in
                    if accept(url: item, keys: keys) {
                        let p = item.standardizedFileURL.path
                        if seenFiles.insert(p).inserted { appendCandidate(url: item, into: &found) }
                    } else if debugScan {
                        log("DBG skip(rec): \(item.lastPathComponent)")
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
        if name.hasSuffix(".lrv") || name.hasSuffix(".lrf") || name.hasSuffix(".thm") { return false } // DJI proxies/thumbnails
        return videoExts.contains(url.pathExtension.lowercased())
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
        // 1) Volume-name override (most reliable if you set it)
        if let volName = c.url.pathComponents.dropFirst(2).first, // "/Volumes/<Name>/…"
           let mapped = volumeBucketOverride[volName] {
            return mapped
        }

        // 2) Path heuristics / filename patterns
        let p = c.url.standardizedFileURL.path.lowercased()

        // DJI Pocket 3 (DCIM/DJI_001, often with .LRF proxies)
        if p.contains("/dcim/dji_001")
            || fm.fileExists(atPath: c.url.deletingPathExtension().appendingPathExtension("LRF").path)
            || fm.fileExists(atPath: c.url.deletingPathExtension().appendingPathExtension("lrf").path) {
            return "Pocket3 Videos"
        }

        // Sony A7C / XAVC S/HS
        if p.contains("/private/m4root/clip") {
            return "A7C Videos"
        }

        // DJI drones / action (100MEDIA)
        if p.contains("/dcim/100media") {
            return "Mini4Pro Videos" // change to "Action4 Videos" if you prefer
        }

        return "Imported Videos" // fallback bucket
    }

    // Build: <Bucket>/<YYYY>/<MM_Month>/<DD>/<filename>
    // …but DO NOT duplicate segments if the user already chose a deeper folder
    // (e.g., they pointed the destination at “…/Pocket3 Videos” or “…/2025/10_October/28”).
    private func buildDestination(for c: ImportCandidate, root: URL) -> URL {
        let cal = Calendar(identifier: .gregorian)
        let y  = cal.component(.year,  from: c.date)
        let m  = cal.component(.month, from: c.date)
        let d  = cal.component(.day,   from: c.date)

        let monthName   = englishMonthFormatter.monthSymbols[m - 1]
        let monthFolder = String(format: "%02d_%@", m, monthName) // "10_October"
        let dayFolder   = String(format: "%02d", d)               // "28"

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
                    Button { mgr.addSourceVolume() } label: {
                        Label("Add SD Card…", systemImage: "plus")
                    }
                    Toggle("Debug scan", isOn: $mgr.debugScan).toggleStyle(.switch)
                    Spacer()
                }

                if mgr.removableVolumes.isEmpty {
                    Text("No removable volumes found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mgr.removableVolumes, id: \.self) { url in
                        HStack {
                            Image(systemName: "externaldrive")
                            Text(url.lastPathComponent)
                            Text(url.path)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Spacer()
                            Button(role: .destructive) {
                                mgr.removeVolumeFromList(for: url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain) // Keeps it from highlighting the whole row
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle()) // Makes the click target bigger
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
                    Label("Scan & Import", systemImage: "square.and.arrow.down")
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
