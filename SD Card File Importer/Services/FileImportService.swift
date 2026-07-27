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

/// Carries the first error from the background write queue back to the read loop.
private nonisolated final class WriteFailure: @unchecked Sendable {
    private var stored: Error?
    private let lock = NSLock()
    func record(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        if stored == nil { stored = error }
    }
    var error: Error? {
        lock.lock(); defer { lock.unlock() }
        return stored
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
    /// trip is latency rather than transfer. That latency stays on the critical
    /// path even with the write pipelining below, which overlaps reads with
    /// writes but not reads with other reads.
    ///
    /// Measured on a UHS-II V60 card, 321 MB clip, warmed up, pipelined —
    /// i.e. the configuration this code actually ships:
    ///
    ///                 to exFAT   to APFS
    ///      1 MB        217        216 MB/s
    ///      2 MB        235        235 MB/s
    ///      4 MB        245        245 MB/s
    ///      8 MB        245        246 MB/s
    ///     16 MB        245        247 MB/s
    ///
    /// Reference points on the same card: `cp` 244 MB/s, `ditto` 241 MB/s,
    /// Finder 226 MB/s, card read ceiling near 250 MB/s.
    ///
    /// Throughput plateaus from 4 MB up, so 4–16 MB are equivalent here; 8 MB
    /// keeps headroom for faster media, where a fixed ~1 ms per request eats a
    /// larger share of a shorter transfer. Do not drop back to 1 MB — that
    /// costs about 12% and is not rescued by pipelining.
    ///
    /// Re-measure against real removable media if changing this. A RAM-backed
    /// disk image has no device latency and shows no difference at all, and the
    /// first read from an idle card is far slower than steady state, so warm up
    /// or whichever size you test first will look worst.
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
        try streamCopy(from: src, to: dst, hashing: hashing, onProgress: onProgress)
    }

    /// The transfer itself, as synchronous blocking work.
    ///
    /// Deliberately not `async`: the loop blocks its thread on real I/O from
    /// start to finish, and the semaphore that applies backpressure to the write
    /// queue is a blocking primitive, which is unavailable from async contexts.
    /// Callers reach this through `copyFile`, which the importer already invokes
    /// on a detached task.
    private func streamCopy(from src: URL, to dst: URL, hashing: Bool, onProgress: (@Sendable (Double) -> Void)?) throws -> SHA256Digest? {
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

            // Reads and writes overlap. Run serially, the card sits idle for the
            // whole of every write; handing writes to a background queue keeps it
            // streaming continuously. Measured on a UHS-II V60 card, 321 MB clip:
            // to exFAT 192 -> 246 MB/s, to APFS 229 -> 247 MB/s. Both then sit at
            // the card's read ceiling, which is the most that is available.
            //
            // Depth 2 is enough — depth 4 measured identically — and it bounds the
            // in-flight buffers to about three chunks, so memory stays flat.
            let writeQueue = DispatchQueue(label: "com.berezone.sdcardimporter.write")
            let inFlight = DispatchSemaphore(value: 2)
            let writeFailure = WriteFailure()

            // Declared after the `outHandle` defer, so it unwinds *before* it: no
            // write can ever be in flight against a closed descriptor, and the
            // catch below cannot delete the file out from under a pending write.
            defer { writeQueue.sync {} }

            while true {
                try Task.checkCancellation()

                // Surface a write failure promptly rather than reading the rest of
                // the file first.
                if let failure = writeFailure.error { throw failure }

                // One pool per read. The loop body has no suspension point, so a
                // whole file's worth of autoreleased read buffers would otherwise
                // accumulate in a single pool until the copy finished.
                let chunk: Data? = try autoreleasepool { () -> Data? in
                    do {
                        return try inHandle.read(upToCount: Self.chunkSize)
                    } catch {
                        throw ImporterError.readFailed(path: src.path)
                    }
                }

                guard let chunkData = chunk, !chunkData.isEmpty else {
                    break // EOF
                }

                // Hashed here rather than on the write queue so chunks are always
                // digested in file order.
                hasher?.update(data: chunkData)
                bytesCopied += UInt64(chunkData.count)

                inFlight.wait()
                writeQueue.async {
                    do {
                        try outHandle.write(contentsOf: chunkData)
                    } catch {
                        writeFailure.record(ImporterError.writeFailed(path: dst.path))
                    }
                    inFlight.signal()
                }

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
            }

            // Every queued write must land before the size check and the digest
            // are trusted.
            writeQueue.sync {}
            if let failure = writeFailure.error { throw failure }

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
