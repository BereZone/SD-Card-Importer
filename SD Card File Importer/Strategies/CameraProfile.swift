import Foundation

protocol CameraProfile {
    var id: String { get }
    func match(url: URL) -> String?
}
