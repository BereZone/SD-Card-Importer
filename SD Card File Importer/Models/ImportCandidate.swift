import Foundation

nonisolated struct ImportCandidate: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let date: Date
    let fileSize: UInt64
}
