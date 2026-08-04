import Foundation

/// Byte and duration formatting shared by the import engine and the views, so a
/// size shown in the contact sheet and the same size shown in the plan bar cannot
/// drift apart.
///
/// Formatters are built per call rather than held in a static. `ByteCountFormatter`
/// and `DateComponentsFormatter` are classes and are not thread-safe, and these are
/// reached from both the main actor and the import session.
nonisolated enum Format {
    static func bytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Time remaining, in words. Non-finite or non-positive input means there is
    /// not yet a usable estimate, which reads better than rendering "0s".
    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 && seconds.isFinite else { return "Estimating..." }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "Unknown"
    }
}
