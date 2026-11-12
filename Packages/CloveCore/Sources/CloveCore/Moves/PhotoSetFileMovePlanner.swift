import Foundation

/// Move Rejects' single suffix for every member, shared with rename replacements.
struct PhotoSetFileMovePlanner {
    let fileSystem: any PhotoFileSystem

    /// Returns nil when every suffix is taken. Reads only; exclusive moves remain authoritative.
    func plan(sources: [URL], folder: URL, maximumSuffixAttempts: Int) throws -> [PhotoFileMove]? {
        for attempt in 0...maximumSuffixAttempts {
            let files = sources.map { source in
                PhotoFileMove(
                    source: source,
                    destination: folder.appendingPathComponent(
                        PhotoFileMoveNaming.suffixed(source.lastPathComponent, attempt: attempt)))
            }
            if try files.allSatisfy({ try !fileSystem.exists(at: $0.destination) }) {
                return files
            }
        }
        return nil
    }
}
