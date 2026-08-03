import SwiftUI
import Combine
import os

/// One event in the import history. The monotonic `id` keeps row identity stable
/// when old entries are trimmed off the front, so trimming doesn't invalidate
/// every row.
///
/// Severity is a field rather than an emoji glued to the front of `text`. It used
/// to be the latter, which meant the view recovered severity by substring-matching
/// the emoji, VoiceOver read "white heavy check mark" before every success, and
/// any message containing one of those characters was miscategorised.
///
/// The timestamp exists because an import can run for forty minutes and a history
/// without times is not a record of anything.
struct LogEntry: Identifiable, Equatable {
    let id: Int
    let text: String
    let severity: Severity
    let time: Date

    var timeLabel: String {
        LogEntry.timeFormatter.string(from: time)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// What a finished import actually did, kept so the app can show an outcome
/// instead of leaving the user to read it out of a scrolling console.
struct ImportResult: Equatable {
    var imported: Int = 0
    var skipped: Int = 0
    var renamed: Int = 0
    var failed: [String] = []
    var bytes: Int64 = 0
    var elapsed: TimeInterval = 0
    var verified: Bool = false
    var wasMove: Bool = false
    var wasDryRun: Bool = false
    var cancelled: Bool = false
    var destination: URL?

    var succeeded: Bool { failed.isEmpty && !cancelled }
}

@MainActor
final class ImportViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.berezone.sdcardimporter", category: "ViewModel")

    /// Upper bound on retained log lines. An import appends one line per file, so
    /// without a cap a large card leaves thousands of strings alive for the rest of
    /// the session — and the log view's per-append work grows with them.
    private static let maxLogLines = 2000
    private var nextLogID = 0

    // Services
    private let permissionService = PermissionService.shared
    private let scanner = FileScanningService()
    private let importer = FileImportService()
    private let profileManager = CameraProfileManager.shared
    private var importTask: Task<Void, Never>?
    
    // State
    @Published var removableVolumes: [URL] = []
    @Published var candidates: [ImportCandidate] = []
    @Published var logLines: [LogEntry] = []
    @Published var isImporting: Bool = false
    /// Set the moment Cancel is pressed. Cancellation is only observed between
    /// files, so without this the button would sit there looking unpressed for
    /// however long the current file takes to finish.
    @Published var isCancelling: Bool = false
    /// Drives the Move confirmation. Lives on the model rather than in a view so
    /// the menu command and the toolbar button share one path to it.
    @Published var isConfirmingMove: Bool = false
    @Published var progress: Double = 0
    /// The outcome of the last import, so the app can show a result instead of
    /// leaving a frozen progress bar and one line at the bottom of a console.
    @Published var lastResult: ImportResult?
    /// Per-file outcomes, so the contact sheet can mark what actually happened
    /// to each row rather than looking identical before and after.
    @Published var importedCandidateIDs = Set<UUID>()
    @Published var failedCandidateIDs = Set<UUID>()
    @Published var currentTransferSpeed: String = ""
    @Published var estimatedTimeRemaining: String = ""
    @Published var debugScan: Bool = false
    
    // User Settings
    @AppStorage("importOptionsJSON") var importOptionsJSON: Data?
    @Published var options = ImportOptions() {
        didSet { saveOptions() }
    }
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

    /// Importing nothing used to be allowed, and reported itself as
    /// "Done. Imported 0/0." — a success message for a no-op.
    var canStartImport: Bool {
        destinationURL != nil && selectedCandidatesCount > 0 && !isImporting
    }

    /// What Start Import is about to do, in one line, shown beside the button.
    /// The destination is the only thing the user cannot otherwise see, so it is
    /// never omitted.
    var importPlanSummary: String? {
        guard let destination = destinationURL, selectedCandidatesCount > 0 else { return nil }
        let verb = options.dryRun ? "Preview" : (options.moveInsteadOfCopy ? "Move" : "Copy")
        let noun = selectedCandidatesCount == 1 ? "file" : "files"
        let size = formatBytes(Double(pendingImportSize))
        return "\(verb) \(selectedCandidatesCount) \(noun) · \(size) → \(destination.lastPathComponent)"
    }

    /// True only for the one combination that destroys the originals.
    var importWillDeleteOriginals: Bool {
        options.moveInsteadOfCopy && !options.dryRun
    }

    /// Names the cards the files are about to leave, so the confirmation says
    /// which physical card is at stake rather than "the source".
    var sourceCardNames: String {
        let names = Set(candidates
            .filter { !disabledCandidates.contains($0.id) }
            .compactMap { getVolumeRootPath(for: $0.url) }
            .map { URL(fileURLWithPath: $0).lastPathComponent })
        return names.sorted().joined(separator: ", ")
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
        loadOptions()
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
        
        // Attempt to reconnect to the destination drive if it just mounted
        if destinationURL == nil, let data = destBookmarkData {
            if let restored = permissionService.restoreDestinationBookmark(from: data) {
                destinationURL = restored
                log("Restored destination drive connection.")
            }
        }
        
        // A mount or unmount during an import must not empty the list the import
        // is working through: the volume list still refreshes, but the candidate
        // set and the user's selection survive until the import finishes.
        if isImporting {
            log("Volume list changed during an import — keeping the current file list.", .caution)
        } else {
            clearCandidates()
        }

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
    
    /// Drops the candidate list and the thumbnails rendered for it. The thumbnail
    /// cache is keyed by file URL, so without this an ejected or rescanned card's
    /// bitmaps stay resident with nothing on screen referencing them.
    private func clearCandidates() {
        candidates = []
        disabledCandidates = []
        Task { await ThumbnailService.shared.clear() }
    }

    func scanForCandidates() {
        log("Scanning volumes…")
        clearCandidates()
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
            log("Pick a destination first.", .failure)
            return
        }

        // Free-space preflight: refuse to start an import that cannot fit.
        if !options.dryRun, let info = getStorageInfo(for: destRoot) {
            let needed = pendingImportSize
            if info.available < needed {
                log("Not enough space on destination: need \(formatBytes(Double(needed))), only \(formatBytes(Double(info.available))) available. Import aborted.", .failure)
                return
            }
        }

        isImporting = true
        isCancelling = false
        defer {
            isImporting = false
            isCancelling = false
        }

        // Snapshot the work before starting. `candidates` and `disabledCandidates`
        // are live @Published state that a mount, unmount or checkbox click can
        // mutate mid-run, and the final tally used to read them back — a card
        // pulled during an import reported "Done. Imported 137/0."
        let plannedCandidates = candidates
        let plannedSkips = disabledCandidates
        let plannedWork = plannedCandidates.filter { !plannedSkips.contains($0.id) }

        let total = max(plannedCandidates.count, 1)
        let startedAt = Date()
        var importedCount = 0
        var skippedCount = 0
        var renamedCount = 0
        var importedBytes: Int64 = 0
        var failedFiles: [String] = []

        lastResult = nil
        importedCandidateIDs = []
        failedCandidateIDs = []
        // Folded as we go rather than collecting every imported URL — the arrays were
        // only ever reduced to a common ancestor at the end, so holding one path per
        // imported file until then was pure accumulation.
        var photoCommonDir: [String]? = nil
        var videoCommonDir: [String]? = nil

        let totalBytes = plannedWork.reduce(0) { $0 + $1.fileSize }
        var completedBytes: UInt64 = 0

        // Rolling window of (timestamp, cumulative bytes) samples, used to compute
        // transfer speed over the last few seconds rather than averaged since the
        // import started. This makes the readout track reality when speed changes
        // mid-import (e.g. a slow file after a run of fast ones), instead of
        // dragging out a stale average.
        let speedWindow: TimeInterval = 5.0
        var speedSamples: [(time: Date, bytes: Double)] = []

        self.currentTransferSpeed = ""
        self.estimatedTimeRemaining = ""

        importTask = Task { @MainActor in
            for (idx, c) in plannedCandidates.enumerated() {
                if Task.isCancelled {
                    self.log("Import cancelled by user.", .caution)
                    break
                }

                if totalBytes > 0 {
                    self.progress = Double(completedBytes) / Double(totalBytes)
                } else {
                    self.progress = Double(idx) / Double(total)
                }

                if plannedSkips.contains(c.id) {
                    continue
                }

                var destURL = buildDestination(for: c, root: destRoot)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    // Same name + same size: almost certainly the same file — skip it.
                    // Same name but different size is a different file (cameras recycle
                    // names after formatting), so import it under a suffixed name
                    // instead of silently dropping it.
                    let existingSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.uint64Value
                    if existingSize == c.fileSize {
                        self.log("Skipping existing: \(destURL.lastPathComponent)", .caution)
                        completedBytes += c.fileSize
                        skippedCount += 1
                        continue
                    } else {
                        destURL = resolveCollision(for: destURL)
                        self.log("Name taken by a different file — importing as \(destURL.lastPathComponent)", .caution)
                        renamedCount += 1
                    }
                }

                if options.dryRun {
                    self.log("Preview: would \(options.moveInsteadOfCopy ? "move" : "copy") → \(destURL.path)")
                    // Counted so a preview run reports "Previewed 482 files"
                    // rather than the old "Done. Imported 0/482", which read as
                    // total failure and was the shipping default.
                    importedCount += 1
                    importedBytes += Int64(c.fileSize)
                    self.importedCandidateIDs.insert(c.id)
                    completedBytes += c.fileSize
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
                                
                                if totalBytes > 0 {
                                    let now = Date()
                                    speedSamples.append((now, totalCopied))
                                    let cutoff = now.addingTimeInterval(-speedWindow)
                                    while speedSamples.count > 1, speedSamples[0].time < cutoff {
                                        speedSamples.removeFirst()
                                    }

                                    if let oldest = speedSamples.first {
                                        let dt = now.timeIntervalSince(oldest.time)
                                        if dt > 0.5 {
                                            let bytesPerSec = (totalCopied - oldest.bytes) / dt
                                            self.currentTransferSpeed = self.formatBytes(bytesPerSec) + "/s"

                                            let remainingBytes = Double(totalBytes) - totalCopied
                                            if remainingBytes > 0 && bytesPerSec > 0 {
                                                self.estimatedTimeRemaining = self.formatTime(remainingBytes / bytesPerSec)
                                            } else if remainingBytes <= 0 {
                                                self.estimatedTimeRemaining = "Finishing..."
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }.value
                    let verified = currentOptions.verifyAfterCopy || currentOptions.moveInsteadOfCopy
                    self.log(verified ? "Imported & verified: \(destURL.lastPathComponent)" : "Imported: \(destURL.lastPathComponent)", .success)
                    importedCount += 1
                    importedBytes += Int64(c.fileSize)
                    self.importedCandidateIDs.insert(c.id)
                    completedBytes += c.fileSize

                    if MediaTypes.isVideoExtension(destURL) {
                        videoCommonDir = self.mergeCommonFolder(videoCommonDir, with: destURL)
                    } else {
                        photoCommonDir = self.mergeCommonFolder(photoCommonDir, with: destURL)
                    }
                } catch is CancellationError {
                    self.log("Import cancelled by user.", .caution)
                    break
                } catch {
                    self.log("Error importing \(c.url.lastPathComponent): \(error.localizedDescription)", .failure)
                    failedFiles.append(c.url.lastPathComponent)
                    self.failedCandidateIDs.insert(c.id)
                    completedBytes += c.fileSize
                }
            }

            self.progress = 1.0
            self.currentTransferSpeed = ""
            self.estimatedTimeRemaining = ""
            let result = ImportResult(
                imported: importedCount,
                skipped: skippedCount,
                renamed: renamedCount,
                failed: failedFiles,
                bytes: importedBytes,
                elapsed: Date().timeIntervalSince(startedAt),
                verified: options.verifyAfterCopy || options.moveInsteadOfCopy,
                wasMove: options.moveInsteadOfCopy,
                wasDryRun: options.dryRun,
                cancelled: Task.isCancelled,
                destination: destRoot
            )
            self.lastResult = result

            self.log("Done. \(result.wasDryRun ? "Previewed" : "Imported") \(importedCount) of \(plannedWork.count).",
                     result.succeeded ? .success : .caution)
            if !failedFiles.isEmpty {
                self.log("\(failedFiles.count) file(s) failed: \(failedFiles.joined(separator: ", "))", .failure)
            }

            if importedCount > 0 && !options.dryRun {
                self.lastImportDate = Date().timeIntervalSince1970
            }

            if options.ejectAfterImport && !options.dryRun && !Task.isCancelled {
                if failedFiles.isEmpty {
                    for vol in removableVolumes {
                        let name = vol.lastPathComponent
                        importer.ejectVolume(url: vol) { error in
                            Task { @MainActor [weak self] in
                                if let error {
                                    self?.log("Eject failed for \(name): \(error.localizedDescription) — don't remove the card yet.", .failure)
                                } else {
                                    self?.log("Ejected: \(name)", .info)
                                }
                            }
                        }
                    }
                } else {
                    self.log("Skipping eject because some files failed to import.", .caution)
                }
            }
            
            if options.openDestinationWhenDone && !options.dryRun && !Task.isCancelled {
                var dirsToOpen = Set<URL>()
                
                if let pd = self.folderURL(from: photoCommonDir) {
                    dirsToOpen.insert(pd)
                }

                if let vd = self.folderURL(from: videoCommonDir) {
                    dirsToOpen.insert(vd)
                }
                
                if dirsToOpen.isEmpty {
                    dirsToOpen.insert(destRoot)
                }
                
                for dir in dirsToOpen {
                    NSWorkspace.shared.open(dir)
                    self.log("Opened destination: \(dir.lastPathComponent)", .info)
                }
            }
        }
        
        await importTask?.value

        // Release the finished task (it captures `self` and the whole import closure)
        // and drop the speed window, so nothing from the run outlives it.
        importTask = nil
        speedSamples = []
    }
    
    /// Finds a destination name that isn't taken, by appending _1, _2, … before the extension.
    private func resolveCollision(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)"
            let candidate = dir.appending(path: name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            i += 1
        }
    }

    /// Narrows a running common-ancestor path to also cover `url`'s directory.
    /// `nil` means "nothing folded in yet", so the first file seeds the ancestor.
    private func mergeCommonFolder(_ current: [String]?, with url: URL) -> [String] {
        let dir = url.deletingLastPathComponent().pathComponents
        guard let current else { return dir }

        var merged: [String] = []
        for i in 0..<min(current.count, dir.count) {
            if current[i] == dir[i] {
                merged.append(current[i])
            } else {
                break
            }
        }
        return merged
    }

    private func folderURL(from components: [String]?) -> URL? {
        guard let components, !components.isEmpty else { return nil }
        var result = URL(fileURLWithPath: "/")
        for comp in components where comp != "/" {
            result.append(path: comp)
        }
        return result
    }
    
    func cancelImport() {
        guard isImporting, !isCancelling else { return }
        isCancelling = true
        log("Cancelling after the current file…")
        importTask?.cancel()
    }

    // MARK: - Formatting Helpers

    func formatBytes(_ bytes: Double) -> String {
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

    /// Folder names come from a free text field, and the result is appended to a
    /// file URL. Unsanitised, "2026/Wedding" silently created a nested folder and
    /// ".." walked up out of the destination entirely.
    static func sanitizeFolderName(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "/", with: "-")
        cleaned = cleaned.replacingOccurrences(of: ":", with: "-")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    func setCustomPhotosBucket(for url: URL, bucket: String) {
        guard let path = getVolumeRootPath(for: url) else { return }
        if bucket == "Auto-Detect" || bucket == "Custom..." {
            customBucketsPhotos.removeValue(forKey: path)
            log("Photos from \(url.lastPathComponent) will use the auto-detected camera folder.")
        } else {
            let clean = Self.sanitizeFolderName(bucket)
            guard !clean.isEmpty else { return }
            customBucketsPhotos[path] = clean
            log("Photos from \(url.lastPathComponent) will go to '\(clean)'.")
        }
        saveCustomBuckets()
    }

    func setCustomVideosBucket(for url: URL, bucket: String) {
        guard let path = getVolumeRootPath(for: url) else { return }
        if bucket == "Auto-Detect" || bucket == "Custom..." {
            customBucketsVideos.removeValue(forKey: path)
            log("Videos from \(url.lastPathComponent) will use the auto-detected camera folder.")
        } else {
            let clean = Self.sanitizeFolderName(bucket)
            guard !clean.isEmpty else { return }
            customBucketsVideos[path] = clean
            log("Videos from \(url.lastPathComponent) will go to '\(clean)'.")
        }
        saveCustomBuckets()
    }
    
    // MARK: - Options Persistence

    private func loadOptions() {
        guard let data = importOptionsJSON,
              let decoded = try? JSONDecoder().decode(ImportOptions.self, from: data)
        else { return }
        options = decoded
    }

    private func saveOptions() {
        importOptionsJSON = try? JSONEncoder().encode(options)
    }

    private func loadCustomBuckets() {
        if let dataPhotos = customSourceBucketsPhotosJSON {
            customBucketsPhotos = (try? JSONDecoder().decode([String: String].self, from: dataPhotos)) ?? [:]
        }
        if let dataVideos = customSourceBucketsVideosJSON {
            customBucketsVideos = (try? JSONDecoder().decode([String: String].self, from: dataVideos)) ?? [:]
        }
        
        if let dropData = customDropdownBucketsJSON, let decoded = try? JSONDecoder().decode([String].self, from: dropData) {
            // "Auto-Detect" and "Custom..." used to be stored as list entries and
            // rendered as if they were folder names. They are picker affordances,
            // so the picker supplies them and they are filtered out of stored
            // lists written by earlier versions.
            dropdownBuckets = decoded.filter { $0 != "Auto-Detect" && $0 != "Custom..." }
        } else {
            // Generic starting points. The previous defaults were one person's
            // camera bag (Pocket3, Action4, A7C, Mini4Pro), which meant every new
            // user's first screen was full of hardware they do not own.
            dropdownBuckets = [
                "Camera",
                "Drone",
                "Action Cam",
                "Phone"
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

    private func cameraBucket(for c: ImportCandidate) -> String {
        let isVideo = MediaTypes.isVideoCategory(c.url)
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
    
    /// Where a single file will actually land, relative to the destination root.
    ///
    /// This is the one thing the interface never used to show. The destination is
    /// a function of the folder template, the per-card folder assignment, the
    /// auto-detected camera profile and the file's EXIF date — four inputs, none
    /// of them visible together — and every mistake this app can make is a
    /// destination mistake. The only preview that existed was hardcoded fiction
    /// in a different tab.
    func previewDestination(for c: ImportCandidate) -> String? {
        guard let root = destinationURL else { return nil }
        let full = buildDestination(for: c, root: root)
        let rootComponents = root.standardizedFileURL.pathComponents
        let fullComponents = full.standardizedFileURL.pathComponents
        guard fullComponents.count > rootComponents.count,
              Array(fullComponents.prefix(rootComponents.count)) == rootComponents else {
            return full.path
        }
        return fullComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// The folder part of `previewDestination`, for grouping and for the plan bar.
    func previewDestinationFolder(for c: ImportCandidate) -> String? {
        guard let path = previewDestination(for: c) else { return nil }
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    /// Candidates belonging to one physical card, for the source list's per-card
    /// counts and for filtering the contact sheet by selection.
    func candidates(onCard cardRoot: String?) -> [ImportCandidate] {
        guard let cardRoot else { return candidates }
        return candidates.filter { getVolumeRootPath(for: $0.url) == cardRoot }
    }

    func selectAll(onCard cardRoot: String?) {
        for c in candidates(onCard: cardRoot) { disabledCandidates.remove(c.id) }
    }

    func deselectAll(onCard cardRoot: String?) {
        for c in candidates(onCard: cardRoot) { disabledCandidates.insert(c.id) }
    }

    /// Re-runs only the files that failed, rather than making the user find and
    /// re-tick them by hand.
    func retryFailedImports() async {
        guard let failed = lastResult?.failed, !failed.isEmpty else { return }
        let failedNames = Set(failed)
        disabledCandidates = Set(candidates
            .filter { !failedNames.contains($0.url.lastPathComponent) }
            .map(\.id))
        await importAll()
    }

    /// Clears the finished-import banner so the plan bar returns to showing the
    /// next operation.
    func dismissResult() {
        lastResult = nil
    }

    /// The single entry point for starting an import, so the button, the menu
    /// command and the keyboard shortcut all pass through the same guard. A
    /// Move deletes the originals, and that must never be reachable without a
    /// confirmation just because the user took a different route to it.
    func requestImport() {
        guard canStartImport else { return }
        if importWillDeleteOriginals {
            isConfirmingMove = true
        } else {
            Task { await importAll() }
        }
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
        // Skip template segments the user's chosen destination already ends with
        // (e.g. dest ".../Footage/A7C" with template "{Camera}/..." shouldn't nest
        // another "A7C"). Only the trailing components are considered — matching
        // anywhere in the path would let an unrelated ancestor folder swallow a
        // template level.
        let existing = Set(url.pathComponents.suffix(desired.count).map { $0.lowercased() })

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
    
    /// Appends to the Activity Log, trimming the oldest lines past the cap.
    ///
    /// The whole type is `@MainActor`, so every caller is already main-isolated and
    /// the append happens inline. It used to hop through a `Task { @MainActor }`,
    /// which allocated a task per line and let log lines land out of order relative
    /// to the state changes they describe.
    private func log(_ s: String, _ severity: Severity = .info) {
        logger.info("\(s, privacy: .public)")
        logLines.append(LogEntry(id: nextLogID, text: s, severity: severity, time: Date()))
        nextLogID += 1
        if logLines.count > Self.maxLogLines {
            logLines.removeFirst(logLines.count - Self.maxLogLines)
        }
    }

    /// Count of entries worth the user's attention, for the history button's badge.
    var unreadProblemCount: Int {
        logLines.filter { $0.severity == .failure || $0.severity == .caution }.count
    }
}
