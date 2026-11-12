import Foundation

/// Executes a confirmed batch in order, stopping at the first file or mark-store failure.
/// The caller rescans after the result. Nothing is retried, persisted or added to undo.
public actor BatchRenamer {
    private let fileSystem: any PhotoFileSystem
    private let store: CloveMarkStore
    private var running = false
    private var observers: [UUID: AsyncStream<BatchRenameProgress>.Continuation] = [:]

    public init(
        store: CloveMarkStore, fileSystem: any PhotoFileSystem = FoundationPhotoFileSystem()
    ) {
        self.store = store
        self.fileSystem = fileSystem
    }

    public func plan(for request: BatchRenameRequest) -> BatchRenamePlan {
        BatchRenamePlanner(fileSystem: fileSystem).plan(for: request)
    }

    /// Precondition: drain `MarkWriteQueue` before planning and executing, and prevent new
    /// writes until this call returns. Writes admitted under old identities would use old paths.
    /// The file facts are checked again before touching anything; any problem refuses the batch.
    public func rename(_ preview: BatchRenamePlan) async throws(BatchRenameRefusal)
        -> BatchRenameResult
    {
        guard !running else { throw .alreadyRunning }
        guard preview.canRename else { throw .problems(preview) }
        let plan = self.plan(for: preview.request)
        guard plan.canRename else { throw .problems(plan) }
        running = true
        defer { running = false }
        var working = plan.rows.filter { !$0.isNoOp }.map { WorkingSet(row: $0) }
        var renamedCount = 0
        var failure: BatchRenameFailure?
        let passes: [RenamePass] =
            plan.requiresTemporaryNames ? [.temporary, .finalName] : [.finalName]
        let temporaryID = String(UUID().uuidString.prefix(12))
        passLoop: for pass in passes {
            for index in working.indices {
                let row = working[index].row
                let stem: String
                let folder: URL
                let relativeFolder: String
                switch pass {
                case .temporary:
                    stem = "clove-rename-\(temporaryID)-\(index + 1)"
                    folder = row.item.set.photoSet.primary.url.deletingLastPathComponent()
                    relativeFolder = row.id.relativeFolderPath
                case .finalName:
                    stem = row.newStem
                    folder = row.files[0].destination.deletingLastPathComponent()
                    relativeFolder = row.destinationRelativeFolder
                }
                let files = working[index].files.map { source in
                    PhotoFileMove(
                        source: source,
                        destination: folder.appendingPathComponent(stem)
                            .appendingPathExtension(source.pathExtension))
                }
                publish(.setStarted(row.id, pass: pass))
                let move = PhotoSetFileMover(fileSystem: fileSystem).move(files, to: folder)
                switch move {
                case .failed(let error):
                    failure = BatchRenameFailure(
                        identity: row.id, error: error,
                        files: files.map { Self.location($0, at: .source) })
                    break passLoop
                case .split(let error, let rollbackFailures, let locations):
                    let reported = locations.map { value in
                        let location: RenameFileLocation.Location
                        switch value.location {
                        case .source: location = .source
                        case .destination: location = .destination
                        case .missing: location = .missing
                        case .unknown: location = .unknown
                        }
                        return Self.location(value.file, at: location)
                    }
                    working[index].files = reported.compactMap(\.url)
                    // A failed first pass can leave some members under its temporary stem.
                    if pass == .temporary { working[index].temporaryStem = stem }
                    failure = BatchRenameFailure(
                        identity: row.id, error: error, rollbackFailures: rollbackFailures,
                        files: reported)
                    break passLoop
                case .moved:
                    working[index].files = files.map(\.destination)
                    working[index].temporaryStem = pass == .temporary ? stem : nil
                    if pass == .finalName { renamedCount += 1 }
                    let newIdentity = PhotoIdentity(
                        folderID: row.id.folderID, relativeFolderPath: relativeFolder, stem: stem)
                    if row.item.set.photoSet.primary.format != .raw {
                        do {
                            // Temporary marks follow their actual files too. Otherwise a swap
                            // would overwrite the next set's old marks before it reaches final.
                            try await store.rekey(from: working[index].identity, to: newIdentity)
                        } catch {
                            failure = BatchRenameFailure(
                                identity: row.id, error: error,
                                files: files.map { Self.location($0, at: .destination) })
                            break passLoop
                        }
                    }
                    working[index].identity = newIdentity
                    publish(.setFinished(row.id, pass: pass))
                }
            }
        }
        let temporarySets = working.compactMap { set -> TemporaryRenameSet? in
            guard let stem = set.temporaryStem else { return nil }
            let files = set.files.filter {
                $0.deletingPathExtension().lastPathComponent == stem
            }
            guard !files.isEmpty else { return nil }
            return TemporaryRenameSet(identity: set.row.id, stem: stem, files: files)
        }
        let result = BatchRenameResult(
            renamedCount: renamedCount, failure: failure, temporarySets: temporarySets)
        publish(.finished(result))
        return result
    }

    public func progressUpdates() -> AsyncStream<BatchRenameProgress> {
        let (stream, continuation) = AsyncStream<BatchRenameProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func publish(_ progress: BatchRenameProgress) {
        for observer in observers.values { observer.yield(progress) }
    }

    private static func location(
        _ file: PhotoFileMove, at location: RenameFileLocation.Location
    ) -> RenameFileLocation {
        RenameFileLocation(source: file.source, destination: file.destination, location: location)
    }

    private struct WorkingSet {
        let row: BatchRenameRow
        var files: [URL]
        var identity: PhotoIdentity
        var temporaryStem: String?

        init(row: BatchRenameRow) {
            self.row = row
            self.files = row.files.map(\.source)
            self.identity = row.id
        }
    }
}
