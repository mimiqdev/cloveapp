import CloveCore
import CloveImaging
import Foundation

/// Read-only Info values from one admitted read. Paths are relative to the opened folder.
struct PhotoInformation: Sendable {
    let image: ImageInformation?
    let relativeFolder: String
    let companions: [String]
    let usesSidecar: Bool
}
