import Foundation

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
    /// The destination root the user chose.
    var destination: URL?
    /// The folders the files actually landed in — the common ancestor of the
    /// imported photos and of the imported videos, which are usually deeper than
    /// `destination` and are not the same folder as each other. Revealing the
    /// root instead of these was showing the user somewhere they did not import
    /// to.
    var destinationFolders: [URL] = []

    var succeeded: Bool { failed.isEmpty && !cancelled }

    /// Where "Show in Finder" should actually go.
    var revealTargets: [URL] {
        destinationFolders.isEmpty ? [destination].compactMap { $0 } : destinationFolders
    }
}
