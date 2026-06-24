import Foundation

/// Custom errors thrown during the file importing process.
enum ImporterError: Error, LocalizedError {
    case fileNotFound(path: String)
    case readFailed(path: String)
    case writeFailed(path: String)
    case unmountFailed(path: String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found at \(path)"
        case .readFailed(let path): return "Failed to read from \(path)"
        case .writeFailed(let path): return "Failed to write to \(path)"
        case .unmountFailed(let path): return "Failed to unmount volume at \(path)"
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
    ///
    /// - Parameters:
    ///   - src: The source URL of the file to copy.
    ///   - dst: The destination URL where the file should be saved.
    ///   - onProgress: An optional closure that is called periodically with the completion percentage (0.0 to 1.0).
    /// - Throws: `ImporterError.fileNotFound`, `ImporterError.readFailed`, or `ImporterError.writeFailed`.
    func copyFile(from src: URL, to dst: URL, onProgress: (@Sendable (Double) -> Void)?) async throws {
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
            let totalSize = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
            var bytesCopied: Double = 0
            
            while true {
                try Task.checkCancellation()
                
                guard let chunk = try? inHandle.read(upToCount: 1024 * 1024) else {
                    throw ImporterError.readFailed(path: src.path)
                }
                if chunk.isEmpty { break }
                
                do {
                    try outHandle.write(contentsOf: chunk)
                    bytesCopied += Double(chunk.count)
                    if totalSize > 0 {
                        onProgress?(bytesCopied / totalSize)
                    }
                } catch {
                    throw ImporterError.writeFailed(path: dst.path)
                }
            }
            
            if let attrs {
                try? fm.setAttributes(attrs, ofItemAtPath: dst.path)
            }
        } catch {
            // If the copy was cancelled or failed, clean up the corrupted partial file
            try? fm.removeItem(at: dst)
            throw error
        }
    }
    
    /// Performs the import of a candidate file to its destination directory.
    ///
    /// Creates intermediate directories if needed. Based on the provided `ImportOptions`,
    /// it will either move the file (deleting from the source) or copy it.
    ///
    /// - Parameters:
    ///   - candidate: The `ImportCandidate` to import.
    ///   - destination: The full destination URL (including file name).
    ///   - options: Configuration options dictating whether to move or copy.
    ///   - onProgress: An optional closure for byte-level progress reporting.
    /// - Throws: Standard `FileManager` errors for directory creation or `ImporterError`s during file transfer.
    func performImport(candidate: ImportCandidate, destination: URL, options: ImportOptions, onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        // Create folders only when actually importing
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if options.moveInsteadOfCopy {
            try fm.moveItem(at: candidate.url, to: destination)   // removes only the SOURCE (SD card) on success
            onProgress?(1.0)
        } else {
            try await copyFile(from: candidate.url, to: destination, onProgress: onProgress)    // never overwrites destination
        }
    }
    
    /// Safely unmounts and ejects the specified volume without prompting the user.
    /// - Parameter url: The URL of the volume to eject.
    func ejectVolume(url: URL) {
        FileManager.default.unmountVolume(
            at: url,
            options: [.withoutUI, .allPartitionsAndEjectDisk],
            completionHandler: { _ in }
        )
    }
}
