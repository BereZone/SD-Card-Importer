import Foundation

/// Runs one import from a fixed plan and reports what happened.
///
/// Separated from `ImportViewModel` because this loop is the part of the app with
/// real consequences — it decides what is skipped, what is renamed, and in Move
/// mode what is deleted — and it was previously a two-hundred-line closure nested
/// inside a method on a type that also owned window state.
///
/// The session takes a snapshot of the work at construction and never reads live
/// view state, so a card mounted or a checkbox clicked mid-run cannot change what
/// is already running. That used to be a real bug: pulling a card during an import
/// reported "Done. Imported 137 of 0."
@MainActor
final class ImportSession {

    /// How the session reports what it is doing. Closures rather than a reference
    /// back to the view model, so the engine carries no dependency on the
    /// interface and can be driven without one.
    struct Reporter {
        var progress: (Double) -> Void = { _ in }
        var rate: (_ speed: String, _ remaining: String) -> Void = { _, _ in }
        var log: (String, Severity) -> Void = { _, _ in }
        var fileImported: (UUID) -> Void = { _ in }
        var fileFailed: (UUID) -> Void = { _ in }
    }

    private let candidates: [ImportCandidate]
    private let skipped: Set<UUID>
    private let destinationRoot: URL
    private let options: ImportOptions
    private let planner: DestinationPlanner
    private let importer: FileImportService
    private let reporter: Reporter

    /// The files this session will actually transfer, which is the plan minus
    /// everything the user unticked. Callers report against this, not against the
    /// full candidate list.
    let work: [ImportCandidate]

    // Tallies, folded as the run proceeds.
    private var importedCount = 0
    private var skippedCount = 0
    private var renamedCount = 0
    private var importedBytes: Int64 = 0
    private var failedFiles: [String] = []
    private var completedBytes: UInt64 = 0

    private var rateEstimator = TransferRateEstimator()
    /// Held so a tick that cannot produce a new estimate can repeat the last one
    /// rather than blanking the field.
    private var lastRemaining = ""

    init(
        candidates: [ImportCandidate],
        skipping skipped: Set<UUID>,
        destinationRoot: URL,
        options: ImportOptions,
        planner: DestinationPlanner,
        importer: FileImportService = FileImportService(),
        reporter: Reporter
    ) {
        self.candidates = candidates
        self.skipped = skipped
        self.destinationRoot = destinationRoot
        self.options = options
        self.planner = planner
        self.importer = importer
        self.reporter = reporter
        self.work = candidates.filter { !skipped.contains($0.id) }
    }

    private func log(_ s: String, _ severity: Severity = .info) {
        reporter.log(s, severity)
    }

    /// Transfers the planned files, one at a time, and returns what happened.
    ///
    /// Files are deliberately not overlapped with each other: it keeps progress
    /// honest and avoids thrashing a card with concurrent reads. The overlap that
    /// does exist is inside `FileImportService`, between a file's reads and its
    /// own writes.
    ///
    /// Cancellation is observed between files. The transfer itself runs on a
    /// detached task, which does not inherit cancellation, so the file in flight
    /// always finishes rather than leaving a partial copy behind.
    func run() async -> ImportResult {
        let startedAt = Date()
        let totalBytes = work.reduce(0) { $0 + $1.fileSize }
        let totalFiles = max(candidates.count, 1)

        var photoCommonDir: [String]? = nil
        var videoCommonDir: [String]? = nil

        reporter.rate("", "")

        for (idx, c) in candidates.enumerated() {
            if Task.isCancelled {
                log("Import cancelled by user.", .caution)
                break
            }

            if totalBytes > 0 {
                reporter.progress(Double(completedBytes) / Double(totalBytes))
            } else {
                reporter.progress(Double(idx) / Double(totalFiles))
            }

            if skipped.contains(c.id) { continue }

            var destURL = planner.destination(for: c, root: destinationRoot)

            if FileManager.default.fileExists(atPath: destURL.path) {
                // Same name and same size: almost certainly the same file, so skip
                // it. Same name but a different size is a different file — cameras
                // recycle names after a format — so it is imported under a suffixed
                // name rather than silently dropped.
                let existingSize = (try? FileManager.default
                    .attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.uint64Value
                if existingSize == c.fileSize {
                    log("Skipping existing: \(destURL.lastPathComponent)", .caution)
                    completedBytes += c.fileSize
                    skippedCount += 1
                    continue
                } else {
                    destURL = DestinationPlanner.resolveCollision(for: destURL)
                    log("Name taken by a different file — importing as \(destURL.lastPathComponent)", .caution)
                    renamedCount += 1
                }
            }

            if options.dryRun {
                log("Preview: would \(options.moveInsteadOfCopy ? "move" : "copy") → \(destURL.path)")
                // Counted so a preview reports "Previewed 482 files" rather than
                // the old "Done. Imported 0 of 482", which read as total failure.
                importedCount += 1
                importedBytes += Int64(c.fileSize)
                reporter.fileImported(c.id)
                completedBytes += c.fileSize
                continue
            }

            do {
                try await transfer(c, to: destURL, index: idx, totalBytes: totalBytes, totalFiles: totalFiles)

                let verified = options.verifyAfterCopy || options.moveInsteadOfCopy
                log(verified
                    ? "Imported & verified: \(destURL.lastPathComponent)"
                    : "Imported: \(destURL.lastPathComponent)", .success)

                importedCount += 1
                importedBytes += Int64(c.fileSize)
                reporter.fileImported(c.id)
                completedBytes += c.fileSize

                if MediaTypes.isVideoExtension(destURL) {
                    videoCommonDir = DestinationPlanner.mergeCommonFolder(videoCommonDir, with: destURL)
                } else {
                    photoCommonDir = DestinationPlanner.mergeCommonFolder(photoCommonDir, with: destURL)
                }
            } catch is CancellationError {
                log("Import cancelled by user.", .caution)
                break
            } catch {
                log("Error importing \(c.url.lastPathComponent): \(error.localizedDescription)", .failure)
                failedFiles.append(c.url.lastPathComponent)
                reporter.fileFailed(c.id)
                completedBytes += c.fileSize
            }
        }

        reporter.progress(1.0)
        reporter.rate("", "")
        rateEstimator.reset()

        return ImportResult(
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
            destination: destinationRoot,
            destinationFolders: [
                DestinationPlanner.folderURL(from: photoCommonDir),
                DestinationPlanner.folderURL(from: videoCommonDir)
            ].compactMap { $0 }
        )
    }

    /// Moves one file's bytes, off the main actor.
    ///
    /// `Task.detached` is deliberate. The project builds with main-actor default
    /// isolation, so awaiting the importer directly would hop straight back to the
    /// main actor and freeze the window for the duration of every file.
    private func transfer(
        _ c: ImportCandidate,
        to destURL: URL,
        index: Int,
        totalBytes: UInt64,
        totalFiles: Int
    ) async throws {
        let currentOptions = options
        let currentImporter = importer

        try await Task.detached(priority: .userInitiated) {
            try await currentImporter.performImport(
                candidate: c,
                destination: destURL,
                options: currentOptions
            ) { byteProgress in
                Task { @MainActor [weak self] in
                    self?.reportFileProgress(
                        byteProgress,
                        for: c,
                        index: index,
                        totalBytes: totalBytes,
                        totalFiles: totalFiles
                    )
                }
            }
        }.value
    }

    /// Folds the in-flight file's progress into the whole-import figures.
    ///
    /// The importer throttles its callbacks at the source, so this runs on a
    /// bounded schedule rather than once per chunk.
    private func reportFileProgress(
        _ fraction: Double,
        for c: ImportCandidate,
        index: Int,
        totalBytes: UInt64,
        totalFiles: Int
    ) {
        let currentFileBytes = Double(c.fileSize) * fraction
        let totalCopied = Double(completedBytes) + currentFileBytes

        guard totalBytes > 0 else {
            // No byte total to divide by — fall back to counting files.
            reporter.progress((Double(index) + fraction) / Double(totalFiles))
            return
        }

        reporter.progress(totalCopied / Double(totalBytes))

        guard let bytesPerSec = rateEstimator.record(cumulativeBytes: totalCopied) else { return }

        let remainingBytes = Double(totalBytes) - totalCopied
        if remainingBytes > 0 && bytesPerSec > 0 {
            lastRemaining = Format.duration(remainingBytes / bytesPerSec)
        } else if remainingBytes <= 0 {
            lastRemaining = "Finishing..."
        }
        // A zero rate with bytes still outstanding leaves the previous estimate in
        // place: dividing by it yields infinity, and blanking the field makes the
        // readout flicker every time the card stalls.

        reporter.rate(Format.bytes(bytesPerSec) + "/s", lastRemaining)
    }
}
