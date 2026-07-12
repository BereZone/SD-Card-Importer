import SwiftUI
import Combine
import os

@MainActor
final class ImportViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.berezone.sdcardimporter", category: "ViewModel")
    
    // Services
    private let permissionService = PermissionService.shared
    private let scanner = FileScanningService()
    private let importer = FileImportService()
    private let profileManager = CameraProfileManager.shared
    private var importTask: Task<Void, Never>?
    
    // State
    @Published var removableVolumes: [URL] = []
    @Published var candidates: [ImportCandidate] = []
    @Published var logLines: [String] = []
    @Published var isImporting: Bool = false
    @Published var progress: Double = 0
    @Published var currentTransferSpeed: String = ""
    @Published var estimatedTimeRemaining: String = ""
    @Published var debugScan: Bool = false
    
    // User Settings
    @Published var options = ImportOptions()
    @Published var sessionIgnoredPaths = Set<String>()
    @Published var disabledCandidates = Set<UUID>()
    
    var selectedCandidatesCount: Int {
        candidates.filter { !disabledCandidates.contains($0.id) }.count
    }
    
    var pendingImportSize: Int64 {
        candidates
            .filter { !disabledCandidates.contains($0.id) }
            .reduce(0) { $0 + Int64($1.fileSize) }
    }
    
    // Buckets
    @AppStorage("customSourceBucketsPhotosJSON") var customSourceBucketsPhotosJSON: Data?
    @AppStorage("customSourceBucketsVideosJSON") var customSourceBucketsVideosJSON: Data?
    @Published var customBucketsPhotos: [String: String] = [:]
    @Published var customBucketsVideos: [String: String] = [:]
    
    @AppStorage("customDropdownBucketsJSON") var customDropdownBucketsJSON: Data?
    @Published var dropdownBuckets: [String] = []
    
    // Optional: map specific volume names to bucket names
    let volumeBucketOverride: [String: String] = [:]

    // Destination
    @AppStorage("destBookmarkData") var destBookmarkData: Data?
    @AppStorage("lastImportDate") var lastImportDate: Double = 0
    
    @Published var destinationURL: URL? = nil {
        didSet {
            if destinationURL != nil {
                storeDestinationBookmark()
                updateDestinationStorage()
            } else {
                destinationStorage = nil
            }
        }
    }
    
    @Published var destinationStorage: (total: Int64, available: Int64)?
    
    // Observers
    private var observers: [NSObjectProtocol] = []
    
    init() {
        loadCustomBuckets()
        observeMounts()
        
        // Restore destination
        if let data = destBookmarkData {
            destinationURL = permissionService.restoreDestinationBookmark(from: data)
        }
        
        // Restore source bookmarks
        _ = permissionService.restoreSourceBookmarks()
        refreshVolumes(autoPrompt: true, autoScan: true)
    }
    
    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }
    
    // MARK: - Logic
    
    func refreshVolumes(autoPrompt: Bool = false, autoScan: Bool = false) {
        log("Refreshing volumes…")
        candidates = []
        disabledCandidates = []
        
        var results: [URL] = permissionService.restoreSourceBookmarks()
        
        let destRoot = destinationVolumeRoot()
        let discovered = scanner.getMountedVolumes(ignoring: sessionIgnoredPaths, destRoot: destRoot)
        
        var existingPaths = Set(results.map { $0.standardizedFileURL.path })
        for d in discovered {
            if !existingPaths.contains(d.standardizedFileURL.path) {
                results.append(d)
                existingPaths.insert(d.standardizedFileURL.path)
            }
        }
        
        results.removeAll { $0.standardizedFileURL.path == "/" }
        
        var byPath: [String: URL] = [:]
        for u in results {
            let path = u.standardizedFileURL.path
            if let scoped = permissionService.scopedURLForVolumePath[path] {
                byPath[path] = scoped
            } else if byPath[path] == nil {
                byPath[path] = u
            }
        }
        
        removableVolumes = byPath.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        let labels = removableVolumes.map { u in
             return permissionService.scopedURLForVolumePath[u.standardizedFileURL.path] != nil ? "\(u.lastPathComponent) (scoped)" : "\(u.lastPathComponent)"
        }
        log("Detected camera cards: \(labels)")

        if autoPrompt {
            let unscoped = removableVolumes.filter { permissionService.scopedURLForVolumePath[$0.standardizedFileURL.path] == nil }
            if !unscoped.isEmpty {
                Task { await requestAccess(to: unscoped, autoScan: autoScan) }
            } else if autoScan && !removableVolumes.isEmpty {
                scanForCandidates()
            }
        } else if autoScan && !removableVolumes.isEmpty {
            scanForCandidates()
        }
    }
    
    func requestAccess(to volumes: [URL], autoScan: Bool = false) async {
        let granted = await permissionService.promptForAccess(to: volumes)
        if !granted.isEmpty {
            permissionService.appendSourceBookmarks(for: granted)
            for u in granted {
                sessionIgnoredPaths.remove(u.standardizedFileURL.path)
            }
            refreshVolumes(autoPrompt: false, autoScan: autoScan)
            log("Granted access for: \(granted.map(\.lastPathComponent))")
        } else {
            log("Access not granted; scanning will show 0 files.")
        }
    }
    
    func addSourceVolume() async {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Grant Access"
        
        if panel.runModal() == .OK {
             permissionService.appendSourceBookmarks(for: panel.urls)
             for u in panel.urls { sessionIgnoredPaths.remove(u.standardizedFileURL.path) }
             refreshVolumes(autoPrompt: false, autoScan: true)
             log("Granted access for: \(panel.urls.map(\.lastPathComponent))")
        }
    }
    
    func scanForCandidates() {
        log("Scanning volumes…")
        log("Scanning volumes…")
        candidates = []
        disabledCandidates = []
        progress = 0
        let vols = removableVolumes
        let totalVols = max(vols.count, 1)
        
        let volumeData: [(URL, URL)] = vols.map {
            let token = permissionService.scopedURLForVolumePath[$0.standardizedFileURL.path] ?? $0
            return ($0, token)
        }
        
        let isDebug = debugScan
        
        let logMsg: @Sendable (String) -> Void = { msg in
            Task { @MainActor [weak self] in self?.log(msg) }
        }
        let updateProgress: @Sendable (Double) -> Void = { p in
            Task { @MainActor [weak self] in self?.progress = p }
        }

        Task {
            let foundCandidates = await Task.detached(priority: .userInitiated) { () -> [ImportCandidate] in
                var results: [ImportCandidate] = []
                let service = FileScanningService()
                
                for (i, (vol, tokenized)) in volumeData.enumerated() {
                    let progressVal = Double(i) / Double(totalVols)
                    logMsg("• \(vol.path)")
                    updateProgress(progressVal)
                    
                    let found = service.scanVolume(vol, tokenizedURL: tokenized, debugScan: isDebug, log: logMsg)
                    results.append(contentsOf: found)
                }
                return results
            }.value
            
            let filter = self.options.dateFilter
            let lastImport = self.lastImportDate
            
            let filteredCandidates = foundCandidates.filter { candidate in
                switch filter {
                case .all:
                    return true
                case .sinceLastImport:
                    return candidate.date.timeIntervalSince1970 > lastImport
                case .today:
                    return Calendar.current.isDateInToday(candidate.date)
                case .last7Days:
                    if let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                        return candidate.date > sevenDaysAgo
                    }
                    return true
                case .customRange:
                    // Normalize dates to start of day for start date, and end of day for end date for inclusivity
                    let start = Calendar.current.startOfDay(for: self.options.customStartDate)
                    let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self.options.customEndDate) ?? self.options.customEndDate
                    return candidate.date >= start && candidate.date <= end
                }
            }
            
            self.candidates = filteredCandidates
            self.progress = 1.0
            self.log("Found \(filteredCandidates.count) files (filtered from \(foundCandidates.count)).")
        }
    }
    
    func importAll() async {
        guard let destRoot = destinationURL else {
            log("❗️ Pick a destination first.")
            return
        }

        isImporting = true
        defer { isImporting = false }
        
        let total = max(candidates.count, 1)
        var importedCount = 0
        var importedPhotoPaths: [URL] = []
        var importedVideoPaths: [URL] = []
        
        let totalBytes = candidates.filter { !disabledCandidates.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
        var completedBytes: UInt64 = 0
        let startTime = Date()
        
        self.currentTransferSpeed = ""
        self.estimatedTimeRemaining = ""
        
        importTask = Task { @MainActor in
            for (idx, c) in candidates.enumerated() {
                if Task.isCancelled {
                    self.log("⚠️ Import cancelled by user.")
                    break
                }
                
                self.progress = Double(idx) / Double(total)
                
                if disabledCandidates.contains(c.id) {
                    continue
                }
                
                let destURL = buildDestination(for: c, root: destRoot)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    self.log("⤵︎ Skipping existing: \(destURL.lastPathComponent)")
                    continue
                }

                if options.dryRun {
                    self.log("DRY RUN: Would create \(destURL.deletingLastPathComponent().path)")
                    self.log("DRY RUN: Would \(options.moveInsteadOfCopy ? "move" : "copy") → \(destURL.path)")
                    continue
                }

                let currentOptions = options
                let currentImporter = importer
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try await currentImporter.performImport(candidate: c, destination: destURL, options: currentOptions) { byteProgress in
                            Task { @MainActor in
                                let currentFileBytes = Double(c.fileSize) * byteProgress
                                let totalCopied = Double(completedBytes) + currentFileBytes
                                
                                if totalBytes > 0 {
                                    self.progress = totalCopied / Double(totalBytes)
                                } else {
                                    self.progress = (Double(idx) + byteProgress) / Double(total)
                                }
                                
                                let elapsed = Date().timeIntervalSince(startTime)
                                if elapsed > 1.0 && totalBytes > 0 {
                                    let bytesPerSec = totalCopied / elapsed
                                    self.currentTransferSpeed = self.formatBytes(bytesPerSec) + "/s"
                                    
                                    let remainingBytes = Double(totalBytes) - totalCopied
                                    if remainingBytes > 0 {
                                        let secondsRemaining = remainingBytes / bytesPerSec
                                        self.estimatedTimeRemaining = self.formatTime(secondsRemaining)
                                    } else {
                                        self.estimatedTimeRemaining = "Finishing..."
                                    }
                                }
                            }
                        }
                    }.value
                    self.log("✅ Imported: \(destURL.lastPathComponent)")
                    importedCount += 1
                    completedBytes += c.fileSize
                    
                    let ext = destURL.pathExtension.lowercased()
                    if ["mp4", "mov", "mxf", "mts", "m4v"].contains(ext) {
                        importedVideoPaths.append(destURL)
                    } else {
                        importedPhotoPaths.append(destURL)
                    }
                } catch is CancellationError {
                    self.log("⚠️ Import cancelled by user.")
                    break
                } catch let error as ImporterError {
                    self.log("❌ Error importing \(c.url.lastPathComponent): \(error.localizedDescription)")
                } catch {
                    self.log("❌ Error importing \(c.url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            self.progress = 1.0
            self.currentTransferSpeed = ""
            self.estimatedTimeRemaining = ""
            self.log("Done. Imported \(importedCount)/\(candidates.count).")
            
            if importedCount > 0 && !options.dryRun {
                self.lastImportDate = Date().timeIntervalSince1970
            }

            if options.ejectAfterImport && !options.dryRun && !Task.isCancelled {
                for vol in removableVolumes {
                    importer.ejectVolume(url: vol)
                    self.log("🔌 Ejected: \(vol.lastPathComponent)")
                }
            }
            
            if options.openDestinationWhenDone && !options.dryRun && !Task.isCancelled {
                var dirsToOpen = Set<URL>()
                
                if let pd = self.deepestCommonFolder(for: importedPhotoPaths) {
                    dirsToOpen.insert(pd)
                }
                
                if let vd = self.deepestCommonFolder(for: importedVideoPaths) {
                    dirsToOpen.insert(vd)
                }
                
                if dirsToOpen.isEmpty {
                    dirsToOpen.insert(destRoot)
                }
                
                for dir in dirsToOpen {
                    NSWorkspace.shared.open(dir)
                    self.log("📂 Opened destination: \(dir.lastPathComponent)")
                }
            }
        }
        
        await importTask?.value
    }
    
    private func deepestCommonFolder(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        var common = first.deletingLastPathComponent().pathComponents
        
        for url in urls.dropFirst() {
            let dir = url.deletingLastPathComponent().pathComponents
            let minLen = min(common.count, dir.count)
            var newCommon: [String] = []
            for i in 0..<minLen {
                if common[i] == dir[i] {
                    newCommon.append(common[i])
                } else {
                    break
                }
            }
            common = newCommon
            if common.isEmpty { break }
        }
        
        guard !common.isEmpty else { return nil }
        
        var result = URL(fileURLWithPath: "/")
        for comp in common where comp != "/" {
            result.append(path: comp)
        }
        return result
    }
    
    func cancelImport() {
        importTask?.cancel()
    }
    
    // MARK: - Formatting Helpers
    
    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds > 0 && seconds.isFinite else { return "Estimating..." }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "Unknown"
    }

    // MARK: - Selection
    
    func toggleSelection(for candidate: ImportCandidate) {
        if disabledCandidates.contains(candidate.id) {
            disabledCandidates.remove(candidate.id)
        } else {
            disabledCandidates.insert(candidate.id)
        }
    }
    
    func selectAll() {
        disabledCandidates.removeAll()
    }
    
    func deselectAll() {
        disabledCandidates = Set(candidates.map(\.id))
    }

    // MARK: - Buckets & Paths
    
    func getVolumeRootPath(for url: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else {
            return url.standardizedFileURL.deletingLastPathComponent().path
        }
        return "/\(components[1])/\(components[2])"
    }

    func setCustomPhotosBucket(for url: URL, bucket: String) {
        guard let path = getVolumeRootPath(for: url) else { return }
        if bucket == "Auto-Detect" || bucket == "Custom..." {
            customBucketsPhotos.removeValue(forKey: path)
        } else {
            customBucketsPhotos[path] = bucket
        }
        saveCustomBuckets()
        log("Set custom photos bucket for \(url.lastPathComponent) to '\(bucket)'")
    }

    func setCustomVideosBucket(for url: URL, bucket: String) {
        guard let path = getVolumeRootPath(for: url) else { return }
        if bucket == "Auto-Detect" || bucket == "Custom..." {
            customBucketsVideos.removeValue(forKey: path)
        } else {
            customBucketsVideos[path] = bucket
        }
        saveCustomBuckets()
        log("Set custom videos bucket for \(url.lastPathComponent) to '\(bucket)'")
    }
    
    private func loadCustomBuckets() {
        if let dataPhotos = customSourceBucketsPhotosJSON {
            customBucketsPhotos = (try? JSONDecoder().decode([String: String].self, from: dataPhotos)) ?? [:]
        }
        if let dataVideos = customSourceBucketsVideosJSON {
            customBucketsVideos = (try? JSONDecoder().decode([String: String].self, from: dataVideos)) ?? [:]
        }
        
        if let dropData = customDropdownBucketsJSON, let decoded = try? JSONDecoder().decode([String].self, from: dropData) {
            dropdownBuckets = decoded
        } else {
            dropdownBuckets = [
                "Auto-Detect",
                "Pocket3",
                "Action4",
                "A7C",
                "Mini4Pro",
                "Phone",
                "Custom..."
            ]
        }
    }

    private func saveCustomBuckets() {
        customSourceBucketsPhotosJSON = try? JSONEncoder().encode(customBucketsPhotos)
        customSourceBucketsVideosJSON = try? JSONEncoder().encode(customBucketsVideos)
    }
    
    func saveDropdownBuckets() {
        customDropdownBucketsJSON = try? JSONEncoder().encode(dropdownBuckets)
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let p = url.path.lowercased()
        let isHyperlapse = p.contains("hyperlapse") || p.contains("timelapse")
        let isPano = p.contains("panorama") || p.contains("pano")
        
        let ext = url.pathExtension.lowercased()
        let videoExts = ["mp4", "mov", "mxf", "mts", "m4v"]
        return isHyperlapse ? true : (isPano ? false : videoExts.contains(ext))
    }

    private func cameraBucket(for c: ImportCandidate) -> String {
        let isVideo = isVideoFile(c.url)
        var customBase: String? = nil
        
        if let root = getVolumeRootPath(for: c.url) {
            customBase = isVideo ? customBucketsVideos[root] : customBucketsPhotos[root]
        }
        
        if customBase == nil, let volName = c.url.pathComponents.dropFirst(2).first, let mapped = volumeBucketOverride[volName] {
            customBase = mapped
        }
        
        if let base = customBase {
            return base // Return literal bucket without appending Categories
        }
        return profileManager.bucket(for: c.url)
    }
    
    private func buildDestination(for c: ImportCandidate, root: URL) -> URL {
        let englishMonthFormatter = DateFormatter()
        englishMonthFormatter.locale = Locale(identifier: "en_US_POSIX")
        englishMonthFormatter.dateFormat = "MMMM"
        
        let cal = Calendar(identifier: .gregorian)
        let y  = cal.component(.year,  from: c.date)
        let m  = cal.component(.month, from: c.date)
        let d  = cal.component(.day,   from: c.date)

        let monthName   = englishMonthFormatter.monthSymbols[m - 1]
        let monthFolder = String(format: "%02d_%@", m, monthName)
        let dayFolder   = String(format: "%02d", d)

        let bucket = cameraBucket(for: c)
        
        let template = options.folderTemplate
        var segments = template.components(separatedBy: "/")
        
        // Remove empty segments
        segments = segments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        var desired: [String] = []
        for seg in segments {
            var s = seg
            s = s.replacingOccurrences(of: "{YYYY}", with: "\(y)")
            s = s.replacingOccurrences(of: "{MM}", with: monthFolder)
            s = s.replacingOccurrences(of: "{DD}", with: dayFolder)
            s = s.replacingOccurrences(of: "{Camera}", with: bucket)
            desired.append(s)
        }
        
        var url = root.standardizedFileURL
        let existing = Set(url.pathComponents.map { $0.lowercased() })

        for seg in desired {
            if !existing.contains(seg.lowercased()) {
                url.append(path: seg)
            }
        }
        
        let fileName = options.renameFiles ? generateFilename(for: c, template: options.renameTemplate) : c.url.lastPathComponent
        return url.appending(path: fileName)
    }
    
    private func generateFilename(for c: ImportCandidate, template: String) -> String {
        let cal = Calendar(identifier: .gregorian)
        let y  = String(format: "%04d", cal.component(.year, from: c.date))
        let m  = String(format: "%02d", cal.component(.month, from: c.date))
        let d  = String(format: "%02d", cal.component(.day, from: c.date))
        
        let camera = cameraBucket(for: c)
        let originalName = c.url.deletingPathExtension().lastPathComponent
        let originalExt = c.url.pathExtension
        
        var result = template
        result = result.replacingOccurrences(of: "{YYYY}", with: y)
        result = result.replacingOccurrences(of: "{MM}", with: m)
        result = result.replacingOccurrences(of: "{DD}", with: d)
        result = result.replacingOccurrences(of: "{Camera}", with: camera)
        result = result.replacingOccurrences(of: "{OriginalName}", with: originalName)
        result = result.replacingOccurrences(of: "{OriginalExtension}", with: originalExt)
        
        // Only append extension if they didn't explicitly include {OriginalExtension}
        if !template.contains("{OriginalExtension}") && !originalExt.isEmpty {
            result += ".\(originalExt)"
        }
        
        return result
    }
    
    // MARK: - Destination Logic
    
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

    private func destinationVolumeRoot() -> URL? {
        guard let dest = destinationURL?.standardizedFileURL else { return nil }
        let c = dest.pathComponents
        guard c.count > 2, c[0] == "/", c[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/\(c[2])")
    }
    
    private func storeDestinationBookmark() {
        guard let url = destinationURL else { destBookmarkData = nil; return }
        destBookmarkData = permissionService.storeDestinationBookmark(for: url)
    }
    
    func updateDestinationStorage() {
        guard let url = destinationURL else { return }
        destinationStorage = getStorageInfo(for: url)
    }
    
    func getStorageInfo(for url: URL) -> (total: Int64, available: Int64)? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            if let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity {
                return (Int64(total), Int64(available))
            }
            return nil
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    func removeVolumeFromList(for url: URL) {
        permissionService.removeVolumeBookmark(for: url, ignoredPaths: &sessionIgnoredPaths)
        if let root = getVolumeRootPath(for: url) {
             customBucketsPhotos.removeValue(forKey: root)
             customBucketsVideos.removeValue(forKey: root)
             saveCustomBuckets()
        }
        refreshVolumes(autoPrompt: false)
    }
    
    func clearIgnoresAndRefresh() {
        sessionIgnoredPaths.removeAll()
        refreshVolumes(autoPrompt: true)
    }
    
    private func observeMounts() {
        let nc = NSWorkspace.shared.notificationCenter
        
        // Use a safe, non-capturing way or simply ignore isolation for this notification which is rare
        // We use MainActor.run explicitly to ensure we are back on main actor before using self properties
        // But we are already on main queue per `queue: .main`.
        // The issue is strictly compile-time check of `self` capture.
        
        // Define handlers that don't capture self in the closure directly if possible, or use Unchecked helper.
        // Easiest fix for "concurrently-executing code" in non-Sendable context: Make ImportViewModel final (done)
        // and ensure we trust the context.
        
        // We will use a dedicated method that returns the closure to separate concerns? No.
        // We will just assume isolation since we requested main queue.
        
        let didMount = nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            // Must handle 'self' carefully.
            guard let self = self else { return }
            // To satisfy compiler, we start a new Task on MainActor. 
            // The warning happens because the BLOCK is not isolated.
            Task { @MainActor in
                self.log("Volume mounted")
                self.refreshVolumes(autoPrompt: true, autoScan: true)
            }
        }
        
        let didUnmount = nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.log("Volume unmounted")
                self.refreshVolumes()
            }
        }
        
        observers = [didMount, didUnmount]
    }
    
    private func log(_ s: String) {
        logger.info("\(s, privacy: .public)")
        Task { @MainActor in
            self.logLines.append(s)
        }
    }
}
