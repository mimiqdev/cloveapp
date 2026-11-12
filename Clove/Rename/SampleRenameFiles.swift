import CloveCore
import Foundation
import Synchronization

/// Synthetic file facts for the sample library. The production rename engine still plans
/// and executes the operation, but every file move stays in memory.
final class SampleRenameFiles: PhotoFileSystem, Sendable {
    private struct State {
        var files: Set<URL>
        var directories: Set<URL>
    }
    private let state: Mutex<State>

    init(sets: [ScannedPhotoSet]) {
        let files = Set(
            sets.flatMap { set in
                set.photoSet.imageFiles.map(\.url) + [set.sidecar.resolvedURL].compactMap { $0 }
            })
        var directories: Set<URL> = []
        for file in files {
            var folder = file.deletingLastPathComponent()
            while folder.path != "/" {
                directories.insert(folder)
                folder = folder.deletingLastPathComponent()
            }
        }
        state = Mutex(State(files: files, directories: directories))
    }

    func fileSize(at url: URL) throws -> Int? {
        state.withLock { $0.files.contains(url) ? 100 : nil }
    }
    func exists(at url: URL) throws -> Bool {
        state.withLock { $0.files.contains(url) || $0.directories.contains(url) }
    }
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        state.withLock { state in
            Array(state.files.union(state.directories)).filter {
                $0.deletingLastPathComponent() == url
            }
        }
    }
    func isDirectory(at url: URL) throws -> Bool { state.withLock { $0.directories.contains(url) } }
    func creationDate(at url: URL) throws -> Date? { Date(timeIntervalSince1970: 1_760_000_000) }
    func volumeIdentifier(of url: URL) throws -> String? { "synthetic" }
    func isReadOnlyVolume(at url: URL) throws -> Bool { false }
    func createDirectory(_ url: URL) throws { state.withLock { _ = $0.directories.insert(url) } }
    func moveExclusively(from source: URL, to destination: URL) throws {
        try state.withLock { state in
            guard state.files.contains(source) else { throw CocoaError(.fileNoSuchFile) }
            guard !state.files.contains(destination) else { throw CocoaError(.fileWriteFileExists) }
            state.files.remove(source)
            state.files.insert(destination)
        }
    }
}
