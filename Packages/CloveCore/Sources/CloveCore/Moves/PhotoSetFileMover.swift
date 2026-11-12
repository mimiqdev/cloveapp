import Foundation

/// A pair of paths for a member of a photo set. Roles and marks belong to the caller.
struct PhotoFileMove: Hashable, Sendable {
    let source: URL
    let destination: URL
}

enum PhotoSetMoveError: Error, Sendable {
    case missingSource(URL)
    case differentVolume
    case notConfirmed(String)
}

struct PhotoFileMoveLocation: Sendable {
    enum Location: Sendable { case source, destination, missing, unknown }
    let file: PhotoFileMove
    let location: Location
}

enum PhotoSetFileMoveResult: Sendable {
    case moved
    case failed(any Error)
    case split(any Error, rollbackFailures: [any Error], files: [PhotoFileMoveLocation])
}

/// The shared exclusive move, confirmation and per-set rollback for moves and renames.
/// There is no copy, delete, retry or retained run state.
struct PhotoSetFileMover: Sendable {
    let fileSystem: any PhotoFileSystem

    func move(_ files: [PhotoFileMove], to folder: URL) -> PhotoSetFileMoveResult {
        var sizes: [URL: Int] = [:]
        do {
            for file in files {
                guard let size = try fileSystem.fileSize(at: file.source) else {
                    throw PhotoSetMoveError.missingSource(file.source)
                }
                sizes[file.source] = size
            }
            if let primary = files.first?.source {
                let source = try? fileSystem.volumeIdentifier(
                    of: primary.deletingLastPathComponent())
                let destination = try? fileSystem.volumeIdentifier(of: folder)
                if let source, let destination, source != destination {
                    throw PhotoSetMoveError.differentVolume
                }
            }
            try fileSystem.createDirectory(folder)
        } catch {
            return .failed(error)
        }

        var moved: [PhotoFileMove] = []
        do {
            for file in files {
                try fileSystem.moveExclusively(from: file.source, to: file.destination)
                moved.append(file)
            }
            try confirm(files, sizes: sizes)
            return .moved
        } catch {
            return rollBack(files, moved: moved, failure: error)
        }
    }

    private func confirm(_ files: [PhotoFileMove], sizes: [URL: Int]) throws {
        for file in files {
            if try fileSystem.exists(at: file.source) {
                throw PhotoSetMoveError.notConfirmed(
                    "\(file.source.lastPathComponent) is still at its source.")
            }
            guard let size = try fileSystem.fileSize(at: file.destination) else {
                throw PhotoSetMoveError.notConfirmed(
                    "\(file.destination.lastPathComponent) is not at its destination.")
            }
            if let expected = sizes[file.source], size != expected {
                throw PhotoSetMoveError.notConfirmed(
                    "\(file.destination.lastPathComponent) changed size during the move.")
            }
        }
    }

    private func rollBack(
        _ files: [PhotoFileMove], moved: [PhotoFileMove], failure: any Error
    ) -> PhotoSetFileMoveResult {
        var rollbackFailures: [any Error] = []
        for file in moved.reversed() {
            do {
                try fileSystem.moveExclusively(from: file.destination, to: file.source)
            } catch {
                rollbackFailures.append(error)
            }
        }
        let restored = Set(moved.map(\.source))
        for file in files {
            do {
                guard try fileSystem.exists(at: file.source) else {
                    throw PhotoSetMoveError.notConfirmed(
                        "\(file.source.lastPathComponent) is not back at its source.")
                }
                if restored.contains(file.source), try fileSystem.exists(at: file.destination) {
                    throw PhotoSetMoveError.notConfirmed(
                        "\(file.destination.lastPathComponent) is still at its destination.")
                }
            } catch {
                rollbackFailures.append(error)
            }
        }
        guard rollbackFailures.isEmpty else {
            return .split(
                failure, rollbackFailures: rollbackFailures,
                files: locations(of: files, moved: Set(moved)))
        }
        return .failed(failure)
    }

    private func locations(
        of files: [PhotoFileMove], moved: Set<PhotoFileMove>
    ) -> [PhotoFileMoveLocation] {
        files.map { file in
            let destination = try? fileSystem.exists(at: file.destination)
            let source = try? fileSystem.exists(at: file.source)
            let prefersDestination = moved.contains(file)
            let first = prefersDestination ? destination : source
            let second = prefersDestination ? source : destination
            let location: PhotoFileMoveLocation.Location
            switch (first, second) {
            case (true, _): location = prefersDestination ? .destination : .source
            case (false, true), (nil, true): location = prefersDestination ? .source : .destination
            case (false, false): location = .missing
            case (false, nil), (nil, false), (nil, nil): location = .unknown
            }
            return PhotoFileMoveLocation(file: file, location: location)
        }
    }
}

/// Collects the images and resolved sidecar, including one written after the scan.
struct PhotoSetFileCollector {
    let fileSystem: any PhotoFileSystem

    func members(of set: ScannedPhotoSet) throws -> [URL] {
        var members = set.photoSet.imageFiles.map(\.url)
        var sidecar = set.sidecar.resolvedURL ?? set.photoSet.sidecarURL
        if sidecar == nil, case .absent = set.sidecar, set.photoSet.primary.format == .raw {
            let proposed = set.photoSet.primary.url.deletingPathExtension()
                .appendingPathExtension("xmp")
            if try fileSystem.exists(at: proposed) { sidecar = proposed }
        }
        if let sidecar, !members.contains(sidecar) { members.append(sidecar) }
        return members
    }
}
