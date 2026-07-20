import Foundation
import CryptoKit

/// Custom errors thrown during the file importing process.
enum ImporterError: Error, LocalizedError {
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
struct FileImportService: Sendable {
    let fm = FileManager.default

    /// Copies a single file from the source URL to the destination URL asynchronously.
    ///
    /// This method reads the file in 1MB chunks to minimize memory usage, allowing the
    /// copying of extremely large files (e.g. 50GB videos) without crashing the app.
    /// It periodically yields to the cooperative thread pool by calling `Task.checkCancellation()`.
    /// The source stream is hashed as it passes through (effectively free — the copy is
    /// bottlenecked on card I/O) and the byte count is checked against the source size.
    ///
    /// - Parameters:
    ///   - src: The source URL of the file to copy.
    ///   - dst: The destination URL where the file should be saved.
    ///   - onProgress: An optional closure that is called periodically with the completion percentage (0.0 to 1.0).
    /// - Returns: The SHA-256 digest of the copied data.
    /// - Throws: `ImporterError.fileNotFound`, `.readFailed`, `.writeFailed`, or `.sizeMismatch`.
    @discardableResult
    func copyFile(from src: URL, to dst: URL, onProgress: (@Sendable (Double) -> Void)?) async throws -> SHA256Digest {
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

            let attrs = try? fm.attributesOfItem(atPath: src.path)
            let totalSize = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            var bytesCopied: UInt64 = 0
            var hasher = SHA256()

            while true {
                try Task.checkCancellation()

                let chunk: Data?
                do {
                    chunk = try inHandle.read(upToCount: 1024 * 1024)
                } catch {
                    throw ImporterError.readFailed(path: src.path)
                }

                guard let chunkData = chunk, !chunkData.isEmpty else {
                    break // EOF
                }

                do {
                    try outHandle.write(contentsOf: chunkData)
                    hasher.update(data: chunkData)
                    bytesCopied += UInt64(chunkData.count)
                    if totalSize > 0 {
                        onProgress?(Double(bytesCopied) / Double(totalSize))
                    }
                } catch {
                    throw ImporterError.writeFailed(path: dst.path)
                }
            }

            if totalSize > 0 && bytesCopied != totalSize {
                throw ImporterError.sizeMismatch(path: dst.path, expected: totalSize, actual: bytesCopied)
            }

            if let attrs {
                try? fm.setAttributes(attrs, ofItemAtPath: dst.path)
            }
            return hasher.finalize()
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
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 1024 * 1024)
            } catch {
                throw ImporterError.readFailed(path: url.path)
            }
            guard let chunkData = chunk, !chunkData.isEmpty else { break }
            hasher.update(data: chunkData)
        }

        guard hasher.finalize() == expected else {
            throw ImporterError.verificationFailed(path: url.path)
        }
    }

    /// Performs the import of a candidate file to its destination directory.
    ///
    /// Creates intermediate directories if needed. Copies always stream in chunks with
    /// an inline source hash and size check. If `options.verifyAfterCopy` is set, the
    /// destination is re-read (uncached) and its hash compared to the source.
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
        if options.moveInsteadOfCopy {
            if isSameVolume(candidate.url, destination.deletingLastPathComponent()) {
                try fm.moveItem(at: candidate.url, to: destination)
                onProgress?(1.0)
                return
            }
            // Cross-volume move: copy, verify, then delete the source. The source is
            // the only copy of the data, so verification here is not optional.
            let digest = try await copyFile(from: candidate.url, to: destination, onProgress: onProgress)
            do {
                try await verifyFile(at: destination, matches: digest)
            } catch {
                try? fm.removeItem(at: destination)
                throw error
            }
            try fm.removeItem(at: candidate.url)
        } else {
            let digest = try await copyFile(from: candidate.url, to: destination, onProgress: onProgress)
            if options.verifyAfterCopy {
                do {
                    try await verifyFile(at: destination, matches: digest)
                } catch {
                    try? fm.removeItem(at: destination)
                    throw error
                }
            }
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
