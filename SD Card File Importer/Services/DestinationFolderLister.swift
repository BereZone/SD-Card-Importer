import Foundation

/// The folders that already exist directly inside the destination.
///
/// The per-card pickers used to offer a hand-maintained list of names kept in
/// Settings, which had no connection to the disk. A name could be assigned that
/// matched no folder, and a folder that did exist could not be chosen without
/// retyping it exactly. Offering what is actually there removes both failures.
///
/// Immediate children only. `DestinationPlanner.sanitizeFolderName` replaces "/"
/// with "-", so a nested path could not survive a round trip through a stored
/// assignment; one level keeps the stored value a plain folder name and leaves
/// `DestinationPlanner` untouched.
nonisolated struct DestinationFolderLister {
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]

    nonisolated static func folders(in root: URL) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: keys) else { return false }
                // Packages are directories, but a photo library or an .app is not
                // somewhere anyone means to file footage.
                return values.isDirectory == true && values.isPackage != true
            }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
