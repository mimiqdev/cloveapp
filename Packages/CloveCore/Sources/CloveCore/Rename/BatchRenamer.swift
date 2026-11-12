import Foundation

/// Executes a confirmed batch in order, stopping at the first file or mark-store failure.
/// The caller rescans after the result. Nothing is retried, persisted or added to undo.
/// If rekeying fails after a confirmed file move, stored marks stay under the previous key.
/// The result reports the failure and counts the files as moved; no recovery is attempted.
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
        var replacedSets: [RenameReplacement] = []
        if case .folder = plan.destination, let first = plan.rows.first {
            let folder = first.files[0].destination.deletingLastPathComponent()
            do {
                for row in plan.rows {
                    let source = try? fileSystem.volumeIdentifier(
                        of: row.item.set.photoSet.primary.url.deletingLastPathComponent())
                    let destination = try? fileSystem.volumeIdentifier(of: folder)
                    if let source, let destination, source != destination {
                        throw PhotoSetMoveError.differentVolume
                    }
                }
                try fileSystem.createDirectory(folder)
            } catch {
                return finish(
                    plan, renamedCount: 0, replacedSets: [], temporarySets: [],
                    failure: BatchRenameFailure(
                        identity: first.id, error: error, files: [],
                        context: "The destination could not be prepared: "))
            }
        }
        for replacement in plan.rows.compactMap(\.replacement) {
            publish(.replacementStarted(replacement.identity))
            let files = replacement.files.map {
                PhotoFileMove(source: $0.source, destination: $0.destination)
            }
            let folder = files[0].destination.deletingLastPathComponent()
            let context = "Existing \(replacement.stem) could not be moved to the rejects folder: "
            let move = PhotoSetFileMover(fileSystem: fileSystem).move(files, to: folder)
            if let failure = Self.moveFailure(
                move, files: files,
                identity: replacement.identity, context: context)
            {
                return finish(
                    plan, renamedCount: 0, replacedSets: replacedSets,
                    temporarySets: [], failure: failure)
            }
            replacedSets.append(replacement)
            if !files.contains(where: { PhotoFile(url: $0.source)?.format == .raw }) {
                let destination = PhotoIdentity(
                    folderID: replacement.identity.folderID,
                    relativeFolderPath: replacement.rejectsRelativeFolder,
                    stem: files[0].destination.deletingPathExtension().lastPathComponent)
                do {
                    try await store.rekey(from: replacement.identity, to: destination)
                } catch {
                    return finish(
                        plan, renamedCount: 0, replacedSets: replacedSets,
                        temporarySets: [],
                        failure: BatchRenameFailure(
                            identity: replacement.identity, error: error,
                            files: files.map { Self.location($0, at: .destination) },
                            context:
                                "Existing \(replacement.stem) moved, but its stored marks remain under the old key: "
                        ))
                }
            }
            publish(.replacementFinished(replacement))
        }
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
                                files: files.map { Self.location($0, at: .destination) },
                                context: "Files moved, but stored marks remain under the old key: ")
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
        return finish(
            plan, renamedCount: renamedCount, replacedSets: replacedSets,
            temporarySets: temporarySets, failure: failure)
    }

    private func finish(
        _ plan: BatchRenamePlan, renamedCount: Int, replacedSets: [RenameReplacement],
        temporarySets: [TemporaryRenameSet], failure: BatchRenameFailure?
    ) -> BatchRenameResult {
        let result = BatchRenameResult(
            renamedCount: renamedCount, replacedSets: replacedSets, destination: plan.destination,
            failure: failure, temporarySets: temporarySets)
        publish(.finished(result))
        return result
    }

    private static func moveFailure(
        _ result: PhotoSetFileMoveResult, files: [PhotoFileMove], identity: PhotoIdentity,
        context: String
    ) -> BatchRenameFailure? {
        switch result {
        case .moved: return nil
        case .failed(let error):
            return BatchRenameFailure(
                identity: identity, error: error,
                files: files.map { location($0, at: .source) }, context: context)
        case .split(let error, let rollbackFailures, let locations):
            let reported = locations.map { value in
                let state: RenameFileLocation.Location
                switch value.location {
                case .source: state = .source
                case .destination: state = .destination
                case .missing: state = .missing
                case .unknown: state = .unknown
                }
                return location(value.file, at: state)
            }
            return BatchRenameFailure(
                identity: identity, error: error,
                rollbackFailures: rollbackFailures, files: reported, context: context)
        }
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
