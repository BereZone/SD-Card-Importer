import Foundation
import Dispatch
import CryptoKit

/// Custom errors thrown during the file importing process.
nonisolated enum ImporterError: Error, LocalizedError {
    case fileNotFound(path: String)
    case readFailed(path: String)
    case writeFailed(path: String)
    case unmountFailed(path: String)
    case sizeMismatch(path: String, expected: UInt64, actual: UInt64)
    case verificationFailed(path: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found at \(path)"
        case .readFailed(let path): return "Failed to read from \(path)"
        case .writeFailed(let path): return "Failed to write to \(path)"
        case .unmountFailed(let path): return "Failed to unmount volume at \(path)"
        case .sizeMismatch(let path, let expected, let actual):
            return "Copy incomplete at \(path): expected \(expected) bytes, wrote \(actual)"
        case .verificationFailed(let path): return "Verification failed: \(path) does not match the source"
        }
    }
}

/// A service responsible for copying or moving files from source media to a destination.
///
/// Explicitly `nonisolated`. The project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without this the whole type
/// is implicitly main-actor isolated — and because `copyFile`'s chunk loop is
/// synchronous, awaiting it from a `Task.detached` would hop straight back to
/// the main actor and block the UI for the entire duration of every file.
nonisolated struct FileImportService: Sendable {
    /// Bytes per read/write in the streaming loops.
    ///
    /// Sized against real hardware, not picked arbitrarily. `F_NOCACHE` disables
    /// kernel readahead, so every read is a synchronous round-trip to the card
    /// with nothing prefetched; the smaller the request, the more of each round
    /// trip is latency rather than transfer. Measured on a UHS-II V60 card
    /// copying a 321 MB clip to internal SSD, warmed up, median of two passes:
    ///
    ///      1 MB  204 MB/s        8 MB  238 MB/s
    ///      2 MB  226 MB/s       16 MB  241 MB/s
    ///      4 MB  239 MB/s
    ///
    /// Reference points on the same card: `cp` 244 MB/s, `ditto` 241 MB/s,
    /// Finder 226 MB/s, and the card itself tops out near 250 MB/s.
    ///
    /// Throughput plateaus from 4 MB up, so anything in 4–16 MB is equivalent.
    /// Do not drop back to 1 MB: that costs about 17% and puts the app below
    /// Finder. Re-measure against real removable media if changing this — a
    /// RAM-backed disk image has no device latency and shows no difference at
    /// all. Measure warmed up, too; the first read from an idle card is far
    /// slower than steady state and will skew whichever size you test first.
    static let chunkSize = 8 * 1024 * 1024

    // Computed rather than stored: `FileManager.default` is a thread-safe
    // singleton, but as a stored property it makes this Sendable struct hold a
    // non-Sendable field.
    var fm: FileManager { FileManager.default }

    /// Copies a single file from the source URL to the destination URL asynchronously.
    ///
    /// This method streams the file in `chunkSize` blocks to keep memory flat, allowing the
    /// copying of extremely large files (e.g. 50GB videos) without crashing the app.
    /// Each chunk is handled inside its own autorelease pool, and both file descriptors
    /// bypass the page cache, so the resident set stays flat for the whole copy rather
    /// than growing with the file.
    /// When `hashing` is set the source stream is digested as it passes through; the
    /// byte count is always checked against the source size regardless.
    ///
    /// Hashing is opt-in because it is not free. Measured on a 2GB file it roughly
    /// halves throughput (0.70s to 1.34s), which is invisible at SD card speeds but
    /// very much not on CFexpress. Only ask for a digest when something will read it.
    ///
    /// - Parameters:
    ///   - src: The source URL of the file to copy.
    ///   - dst: The destination URL where the file should be saved.
    ///   - hashing: Whether to compute a SHA-256 of the source stream.
    ///   - onProgress: An optional closure that is called periodically with the completion percentage (0.0 to 1.0).
    /// - Returns: The SHA-256 digest of the copied data, or `nil` when `hashing` is false.
    /// - Throws: `ImporterError.fileNotFound`, `.readFailed`, `.writeFailed`, or `.sizeMismatch`.
    @discardableResult
    func copyFile(from src: URL, to dst: URL, hashing: Bool, onProgress: (@Sendable (Double) -> Void)?) async throws -> SHA256Digest? {
        guard let inHandle = try? FileHandle(forReadingFrom: src) else {
            throw ImporterError.fileNotFound(path: src.path)
        }
        defer { try? inHandle.close() }

        guard fm.createFile(atPath: dst.path, contents: nil) else {
            throw ImporterError.writeFailed(path: dst.path)
        }

        do {
            guard let outHandle = try? FileHandle(forWritingTo: dst) else {
                throw ImporterError.writeFailed(path: dst.path)
            }
            defer { try? outHandle.close() }

            // Neither side of a card import benefits from the page cache: the source
            // is read exactly once, and the destination is only re-read by
            // `verifyFile`, which sets F_NOCACHE itself. Without this, a 50GB import
            // parks 50GB of pages in the kernel's cache — memory that shows up as
            // never coming back after an import, and that evicts whatever the user
            // actually had cached.
            _ = fcntl(inHandle.fileDescriptor, F_NOCACHE, 1)
            _ = fcntl(outHandle.fileDescriptor, F_NOCACHE, 1)

            let attrs = try? fm.attributesOfItem(atPath: src.path)
            let totalSize = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            var bytesCopied: UInt64 = 0
            var hasher: SHA256? = hashing ? SHA256() : nil

            // Progress is throttled at the source. The caller hops to the main actor
            // on every callback, so one callback per chunk means thousands of queued
            // main-actor jobs on a large import — each retaining its captured closure
            // until it runs. Emitting on a 0.5%-or-100ms edge keeps the bar smooth
            // while bounding that queue.
            var lastReportedFraction = 0.0
            var lastReportTime = DispatchTime.now()
            let minFractionStep = 0.005
            let minReportInterval: UInt64 = 100 * NSEC_PER_MSEC

            while true {
                try Task.checkCancellation()

                // One pool per chunk. The loop body has no suspension point, so a
                // whole file's worth of autoreleased read buffers would otherwise
                // accumulate in a single pool until the copy finished.
                let more = try autoreleasepool { () -> Bool in
                    let chunk: Data?
                    do {
                        chunk = try inHandle.read(upToCount: Self.chunkSize)
                    } catch {
                        throw ImporterError.readFailed(path: src.path)
                    }

                    guard let chunkData = chunk, !chunkData.isEmpty else {
                        return false // EOF
                    }

                    do {
                        try outHandle.write(contentsOf: chunkData)
                    } catch {
                        throw ImporterError.writeFailed(path: dst.path)
                    }

                    hasher?.update(data: chunkData)
                    bytesCopied += UInt64(chunkData.count)

                    if totalSize > 0, let onProgress {
                        let fraction = Double(bytesCopied) / Double(totalSize)
                        let now = DispatchTime.now()
                        let elapsed = now.uptimeNanoseconds - lastReportTime.uptimeNanoseconds
                        if fraction >= 1.0
                            || (fraction - lastReportedFraction >= minFractionStep
                                && elapsed >= minReportInterval) {
                            lastReportedFraction = fraction
                            lastReportTime = now
                            onProgress(fraction)
                        }
                    }
                    return true
                }

                if !more { break }
            }

            if totalSize > 0 && bytesCopied != totalSize {
                throw ImporterError.sizeMismatch(path: dst.path, expected: totalSize, actual: bytesCopied)
            }

            if let attrs {
                try? fm.setAttributes(attrs, ofItemAtPath: dst.path)
            }
            return hasher?.finalize()
        } catch {
            // If the copy was cancelled or failed, clean up the corrupted partial file
            try? fm.removeItem(at: dst)
            throw error
        }
    }

    /// Re-reads a file from disk and checks its SHA-256 digest against an expected value.
    ///
    /// Sets `F_NOCACHE` on the read so the data comes from the physical medium rather
    /// than the page cache — right after a copy the file is still cached in RAM, and a
    /// cached read would verify nothing about what actually landed on disk.
    func verifyFile(at url: URL, matches expected: SHA256Digest) async throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ImporterError.readFailed(path: url.path)
        }
        defer { try? handle.close() }
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            // Pool per chunk, for the same reason as `copyFile`: no suspension point
            // in the loop means one pool would otherwise span the whole file.
            let more = try autoreleasepool { () -> Bool in
                let chunk: Data?
                do {
                    chunk = try handle.read(upToCount: Self.chunkSize)
                } catch {
                    throw ImporterError.readFailed(path: url.path)
                }
                guard let chunkData = chunk, !chunkData.isEmpty else { return false }
                hasher.update(data: chunkData)
                return true
            }
            if !more { break }
        }

        guard hasher.finalize() == expected else {
            throw ImporterError.verificationFailed(path: url.path)
        }
    }

    /// Performs the import of a candidate file to its destination directory.
    ///
    /// Creates intermediate directories if needed. Copies stream in chunks with a size
    /// check. If the copy will be verified, the source is also hashed as it streams and
    /// the destination is then re-read (uncached) and compared.
    ///
    /// Move mode never deletes the source until the destination copy has been fully
    /// verified — a failed verification keeps the source intact and removes the bad
    /// copy. (A move within the same volume is a metadata-only rename and needs no
    /// verification.)
    ///
    /// - Parameters:
    ///   - candidate: The `ImportCandidate` to import.
    ///   - destination: The full destination URL (including file name).
    ///   - options: Configuration options dictating whether to move or copy, and whether to verify.
    ///   - onProgress: An optional closure for byte-level progress reporting.
    /// - Throws: Standard `FileManager` errors for directory creation or `ImporterError`s during transfer/verification.
    func performImport(candidate: ImportCandidate, destination: URL, options: ImportOptions, onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        // Create folders only when actually importing
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // A move within one volume is a rename: no bytes travel, nothing to verify.
        if options.moveInsteadOfCopy,
           isSameVolume(candidate.url, destination.deletingLastPathComponent()) {
            try fm.moveItem(at: candidate.url, to: destination)
            onProgress?(1.0)
            return
        }

        // A cross-volume move deletes the source afterwards, so its copy must be
        // verified whatever the user asked for. A plain copy only needs a digest if
        // verification is actually going to read it — hashing a stream nobody checks
        // costs roughly half the transfer throughput on fast media.
        let mustVerify = options.moveInsteadOfCopy || options.verifyAfterCopy

        let digest = try await copyFile(
            from: candidate.url,
            to: destination,
            hashing: mustVerify,
            onProgress: onProgress
        )

        if mustVerify {
            do {
                guard let digest else {
                    throw ImporterError.verificationFailed(path: destination.path)
                }
                try await verifyFile(at: destination, matches: digest)
            } catch {
                try? fm.removeItem(at: destination)
                throw error
            }
        }

        if options.moveInsteadOfCopy {
            try fm.removeItem(at: candidate.url)
        }
    }

    private func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let idA = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let idB = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        else { return false }
        return idA.isEqual(idB)
    }

    /// Safely unmounts and ejects the specified volume without prompting the user.
    /// - Parameters:
    ///   - url: The URL of the volume to eject.
    ///   - completion: Called with the error if ejecting failed, or nil on success.
    func ejectVolume(url: URL, completion: @escaping @Sendable (Error?) -> Void) {
        FileManager.default.unmountVolume(
            at: url,
            options: [.withoutUI, .allPartitionsAndEjectDisk],
            completionHandler: completion
        )
    }
}
