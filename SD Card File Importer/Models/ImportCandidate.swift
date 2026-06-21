import Foundation

struct ImportCandidate: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let fileSize: UInt64
}
