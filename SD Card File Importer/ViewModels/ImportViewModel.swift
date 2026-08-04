import SwiftUI
import Combine
import os

/// The window's state, and the entry points the interface calls into.
///
/// Deliberately a façade rather than an engine. The work itself lives in types
/// that do not know the interface exists — `ImportSession` runs a transfer,
/// `DestinationPlanner` decides where files go, `FileScanningService` finds them —
/// and this holds the published state those parts report into, because that is
/// what SwiftUI binds to.
///
/// The rest of the type is split by concern:
/// - `ImportViewModel+Cards` — finding cards, permission, scanning
/// - `ImportViewModel+Persistence` — settings that outlive a launch
@MainActor
final class ImportViewModel: ObservableObject {
    let logger = Logger(subsystem: "com.berezone.sdcardimporter", category: "ViewModel")

    /// Upper bound on retained log lines. An import appends one line per file, so
    /// without a cap a large card leaves thousands of strings alive for the rest of
    /// the session — and the log view's per-append work grows with them.
    private static let maxLogLines = 2000
    private var nextLogID = 0

    // MARK: - Services

    let permissionService = PermissionService.shared
    let scanner = FileScanningService()
    private let importer = FileImportService()
    private var importTask: Task<ImportResult, Never>?

    // MARK: - State

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

    // MARK: - User settings

    @AppStorage("importOptionsJSON") var importOptionsJSON: Data?
    @Published var options = ImportOptions() {
        didSet { saveOptions() }
    }
    @Published var sessionIgnoredPaths = Set<String>()
    @Published var disabledCandidates = Set<UUID>()

    @AppStorage("customSourceBucketsPhotosJSON") var customSourceBucketsPhotosJSON: Data?
    @AppStorage("customSourceBucketsVideosJSON") var customSourceBucketsVideosJSON: Data?
    @Published var customBucketsPhotos: [String: String] = [:]
    @Published var customBucketsVideos: [String: String] = [:]

    @AppStorage("customDropdownBucketsJSON") var customDropdownBucketsJSON: Data?
    @Published var dropdownBuckets: [String] = []

    /// Optional map of specific volume names to folder names.
    let volumeBucketOverride: [String: String] = [:]

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

    var observers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    init() {
        loadOptions()
        loadCustomBuckets()
        observeMounts()

        if let data = destBookmarkData {
            destinationURL = permissionService.restoreDestinationBookmark(from: data)
        }

        _ = permissionService.restoreSourceBookmarks()
        refreshVolumes(autoPrompt: true, autoScan: true)
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }

    // MARK: - The plan

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
            .compactMap { DestinationPlanner.volumeRootPath(for: $0.url) }
            .map { URL(fileURLWithPath: $0).lastPathComponent })
        return names.sorted().joined(separator: ", ")
    }

    // MARK: - Running an import

    /// The single entry point for starting an import, so the button, the menu
    /// command and the keyboard shortcut all pass through the same guard. A Move
    /// deletes the originals, and that must never be reachable without a
    /// confirmation just because the user took a different route to it.
    func requestImport() {
        guard canStartImport else { return }
        if importWillDeleteOriginals {
            isConfirmingMove = true
        } else {
            Task { await importAll() }
        }
    }

    /// Preflights the import, hands the transfer to an `ImportSession`, and acts
    /// on the result. Everything the run itself does lives in the session; what is
    /// left here is what happens either side of it.
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

        lastResult = nil
        importedCandidateIDs = []
        failedCandidateIDs = []
        currentTransferSpeed = ""
        estimatedTimeRemaining = ""

        let session = ImportSession(
            candidates: candidates,
            skipping: disabledCandidates,
            destinationRoot: destRoot,
            options: options,
            planner: makePlanner(),
            importer: importer,
            reporter: ImportSession.Reporter(
                progress: { [weak self] in self?.progress = $0 },
                rate: { [weak self] speed, remaining in
                    self?.currentTransferSpeed = speed
                    self?.estimatedTimeRemaining = remaining
                },
                log: { [weak self] text, severity in self?.log(text, severity) },
                fileImported: { [weak self] in self?.importedCandidateIDs.insert($0) },
                fileFailed: { [weak self] in self?.failedCandidateIDs.insert($0) }
            )
        )
        let plannedCount = session.work.count

        // Wrapped in a stored task so Cancel has something to cancel. Released
        // afterwards because it captures the session and everything the session
        // captured.
        importTask = Task { await session.run() }
        let result = await importTask?.value
        importTask = nil

        guard let result else { return }
        lastResult = result

        log("Done. \(result.wasDryRun ? "Previewed" : "Imported") \(result.imported) of \(plannedCount).",
            result.succeeded ? .success : .caution)
        if !result.failed.isEmpty {
            log("\(result.failed.count) file(s) failed: \(result.failed.joined(separator: ", "))", .failure)
        }

        if result.imported > 0 && !result.wasDryRun {
            lastImportDate = Date().timeIntervalSince1970
        }

        guard !result.wasDryRun && !result.cancelled else { return }

        if options.ejectAfterImport {
            ejectSourceVolumes(afterFailures: result.failed)
        }
        if options.openDestinationWhenDone {
            openLandingFolders(for: result)
        }
    }

    func cancelImport() {
        guard isImporting, !isCancelling else { return }
        isCancelling = true
        log("Cancelling after the current file…")
        importTask?.cancel()
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

    /// A card is only ejected once everything on it arrived. Ejecting after a
    /// partial import would take away the only copy of the files that failed.
    private func ejectSourceVolumes(afterFailures failures: [String]) {
        guard failures.isEmpty else {
            log("Skipping eject because some files failed to import.", .caution)
            return
        }
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
    }

    /// Opens the folders the files actually landed in, which are usually deeper
    /// than the destination root and are not the same folder for photos and video.
    private func openLandingFolders(for result: ImportResult) {
        for dir in Set(result.revealTargets) {
            NSWorkspace.shared.open(dir)
            log("Opened destination: \(dir.lastPathComponent)", .info)
        }
    }

    // MARK: - Destinations

    /// A snapshot of everything that decides where files go, handed to whatever
    /// needs to resolve a path. Built per call so it can never answer from a stale
    /// copy of the user's settings.
    func makePlanner() -> DestinationPlanner {
        DestinationPlanner(
            options: options,
            customBucketsPhotos: customBucketsPhotos,
            customBucketsVideos: customBucketsVideos,
            volumeBucketOverride: volumeBucketOverride
        )
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
        return makePlanner().relativeDestination(for: c, root: root)
    }

    /// The folder part of `previewDestination`, for grouping and for the plan bar.
    func previewDestinationFolder(for c: ImportCandidate) -> String? {
        guard let path = previewDestination(for: c) else { return nil }
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    func getVolumeRootPath(for url: URL) -> String? {
        DestinationPlanner.volumeRootPath(for: url)
    }

    static func sanitizeFolderName(_ raw: String) -> String {
        DestinationPlanner.sanitizeFolderName(raw)
    }

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

    func updateDestinationStorage() {
        guard let url = destinationURL else { return }
        destinationStorage = getStorageInfo(for: url)
    }

    func getStorageInfo(for url: URL) -> (total: Int64, available: Int64)? {
        guard let values = try? url.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        ), let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity
        else { return nil }
        return (Int64(total), Int64(available))
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

    /// Candidates belonging to one physical card, for the source list's per-card
    /// counts and for filtering the contact sheet by selection.
    func candidates(onCard cardRoot: String?) -> [ImportCandidate] {
        guard let cardRoot else { return candidates }
        return candidates.filter { DestinationPlanner.volumeRootPath(for: $0.url) == cardRoot }
    }

    func selectAll(onCard cardRoot: String?) {
        for c in candidates(onCard: cardRoot) { disabledCandidates.remove(c.id) }
    }

    func deselectAll(onCard cardRoot: String?) {
        for c in candidates(onCard: cardRoot) { disabledCandidates.insert(c.id) }
    }

    // MARK: - History

    /// Appends to the Activity Log, trimming the oldest lines past the cap.
    ///
    /// The whole type is `@MainActor`, so every caller is already main-isolated and
    /// the append happens inline. It used to hop through a `Task { @MainActor }`,
    /// which allocated a task per line and let log lines land out of order relative
    /// to the state changes they describe.
    func log(_ s: String, _ severity: Severity = .info) {
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

    // MARK: - Formatting

    func formatBytes(_ bytes: Double) -> String {
        Format.bytes(bytes)
    }
}
