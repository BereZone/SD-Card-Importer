import Foundation

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
