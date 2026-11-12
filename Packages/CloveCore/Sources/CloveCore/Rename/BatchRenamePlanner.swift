import Foundation

/// Reads file-system facts without creating folders or changing files or marks.
public struct BatchRenamePlanner: Sendable {
    private let fileSystem: any PhotoFileSystem

    public init(fileSystem: any PhotoFileSystem = FoundationPhotoFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func plan(for request: BatchRenameRequest) -> BatchRenamePlan {
        let (destination, destinationProblems) = resolveDestination(for: request)
        var rows = request.items.enumerated().map { index, item in
            row(
                for: item, index: index, request: request, destination: destination,
                destinationProblems: destinationProblems)
        }
        let sourceCounts = Dictionary(grouping: rows.indices, by: { rows[$0].id })
        for indices in sourceCounts.values where indices.count > 1 {
            for index in indices { rows[index].problems.append(.duplicateSource(rows[index].id)) }
        }
        rows = checkingDuplicateTargets(rows)
        let sources = Set(rows.flatMap(\.files).map { PhotoFilePath.canonical($0.source) })
        let sourceStems = Set(
            rows.map { row in
                Self.stemKey(
                    folder: row.item.set.photoSet.primary.url.deletingLastPathComponent(),
                    stem: row.oldStem)
            })
        var directories: [String: [String: [URL]]] = [:]
        var directoryErrors: [String: String] = [:]
        for index in rows.indices {
            guard let file = rows[index].files.first else { continue }
            do {
                let folder = file.destination.deletingLastPathComponent()
                let folderKey = PhotoFilePath.canonical(folder)
                if directories[folderKey] == nil, directoryErrors[folderKey] == nil {
                    do {
                        let entries =
                            try fileSystem.exists(at: folder)
                            ? fileSystem.contentsOfDirectory(at: folder) : []
                        directories[folderKey] = Dictionary(grouping: entries) {
                            $0.deletingPathExtension().lastPathComponent.lowercased()
                        }
                    } catch {
                        directoryErrors[folderKey] = String(describing: error)
                    }
                }
                if let error = directoryErrors[folderKey] {
                    let problem = RenameProblem.fileSystem(error)
                    if !rows[index].problems.contains(problem) {
                        rows[index].problems.append(problem)
                    }
                }
                let existingTargets =
                    directories[folderKey]?[rows[index].newStem.lowercased()] ?? []
                let replacedFiles = existingTargets.filter { existing in
                    !sources.contains(PhotoFilePath.canonical(existing))
                        && (PhotoFile(url: existing) != nil
                            || existing.pathExtension.lowercased() == "xmp")
                }
                if !replacedFiles.isEmpty {
                    rows[index].replacement = try RenameReplacementPlanner(fileSystem: fileSystem)
                        .plan(files: replacedFiles, row: rows[index], request: request)
                }
            } catch {
                rows[index].problems.append(.fileSystem(String(describing: error)))
            }
        }
        let needsTemporary = rows.filter { !$0.isNoOp }.contains { row in
            guard let destination = row.files.first?.destination else { return false }
            return sourceStems.contains(
                Self.stemKey(folder: destination.deletingLastPathComponent(), stem: row.newStem))
        }
        return BatchRenamePlan(
            request: request, rows: rows, requiresTemporaryNames: needsTemporary,
            destination: destination)
    }

    /// Kept separate so duplicate detection can also be tested with adversarial target facts.
    func checkingDuplicateTargets(_ input: [BatchRenameRow]) -> [BatchRenameRow] {
        var rows = input
        let targets = Dictionary(grouping: rows.indices) { index in
            let row = rows[index]
            let folder =
                row.files.first?.destination.deletingLastPathComponent()
                ?? row.item.set.photoSet.primary.url.deletingLastPathComponent()
            return Self.stemKey(folder: folder, stem: row.newStem)
        }
        for indices in targets.values where indices.count > 1 {
            for index in indices {
                if let target = rows[index].files.first?.destination {
                    rows[index].problems.append(.duplicateTarget(target))
                }
            }
        }
        return rows
    }

    private func row(
        for item: RenameItem, index: Int, request: BatchRenameRequest,
        destination: RenameDestination, destinationProblems: [RenameProblem]
    ) -> BatchRenameRow {
        let set = item.set
        let primary = set.photoSet.primary.url
        let sourceFolder = primary.deletingLastPathComponent()
        let relativeFolder = set.id.relativeFolderPath
        let expectedFolder =
            relativeFolder.isEmpty
            ? request.rootURL
            : request.rootURL.appendingPathComponent(relativeFolder, isDirectory: true)
        var problems = destinationProblems
        let destinationFolder: URL
        let destinationRelativeFolder: String
        switch destination {
        case .inPlace:
            destinationFolder = sourceFolder
            destinationRelativeFolder = relativeFolder
        case .folder(let name):
            problems += Self.nameProblems(name)
            destinationFolder = request.rootURL.appendingPathComponent(name, isDirectory: true)
            destinationRelativeFolder = name
        }
        if !PhotoFilePath.matches(sourceFolder, expectedFolder)
            || !Self.isInside(sourceFolder, root: request.rootURL)
            || !Self.isInside(destinationFolder, root: request.rootURL)
        {
            problems.append(.outsideOpenedFolder)
        }
        if case .ambiguous(let candidates) = set.sidecar {
            problems.append(.ambiguousSidecar(candidates))
        }
        let members = PhotoSetFileCollector(fileSystem: fileSystem).members(of: set)
        if members.contains(where: {
            !PhotoFilePath.matches($0.deletingLastPathComponent(), sourceFolder)
        }) {
            problems.append(.outsideOpenedFolder)
        }
        let template = request.template
        let (sequence, overflow) = template.sequenceStart.addingReportingOverflow(index)
        if overflow { problems.append(.sequenceOverflow) }
        let validSequence = template.sequenceStart >= 0 && (1...255).contains(template.digits)
        if !validSequence { problems.append(.invalidSequence) }
        let number = String(overflow ? template.sequenceStart : sequence)
        let padding = validSequence ? max(0, template.digits - number.count) : 0
        var dateText = ""
        if template.includesCaptureDate {
            do {
                if let wall = item.captureWallTime {
                    dateText = Self.dateText(wall, timeZone: .gmt)
                } else if let creation = try fileSystem.creationDate(at: primary) {
                    dateText = Self.dateText(creation, timeZone: request.timeZone)
                } else {
                    problems.append(.dateUnavailable)
                }
            } catch {
                problems.append(.fileSystem(String(describing: error)))
            }
            dateText += template.dateSeparator
        }
        let stem = template.prefix + dateText + String(repeating: "0", count: padding) + number
        problems += Self.nameProblems(stem)
        let files = members.map { source in
            let name = stem + "." + source.pathExtension
            if name.utf8.count > 255 { problems.append(.nameTooLong(name)) }
            return RenameFile(
                source: source, destination: destinationFolder.appendingPathComponent(name))
        }
        let oldStem = primary.deletingPathExtension().lastPathComponent
        let noOp =
            PhotoFilePath.matches(sourceFolder, destinationFolder)
            && oldStem.caseInsensitiveCompare(stem) == .orderedSame
        return BatchRenameRow(
            item: item, oldStem: oldStem, newStem: stem,
            destinationRelativeFolder: destinationRelativeFolder, files: files,
            problems: Array(Set(problems)).sorted {
                String(describing: $0) < String(describing: $1)
            },
            isNoOp: noOp)
    }

    private func resolveDestination(for request: BatchRenameRequest)
        -> (RenameDestination, [RenameProblem])
    {
        guard case .folder(let name) = request.destination else { return (.inPlace, []) }
        var problems = Self.nameProblems(name)
        if name.caseInsensitiveCompare(request.rejectsFolderName.rawValue) == .orderedSame {
            problems.append(.rejectsDestination(name))
        }
        guard problems.isEmpty else { return (request.destination, problems) }
        do {
            if let existing = try fileSystem.child(named: name, in: request.rootURL) {
                if try !fileSystem.isDirectory(at: existing) {
                    problems.append(.destinationIsFile(existing))
                }
                return (.folder(existing.lastPathComponent), problems)
            }
        } catch {
            problems.append(.fileSystem(String(describing: error)))
        }
        return (request.destination, problems)
    }

    static func nameProblems(_ name: String) -> [RenameProblem] {
        var problems: [RenameProblem] = []
        let forbidden = CharacterSet(charactersIn: "/:\\*?\"<>|")
            .union(.controlCharacters)
        if name.isEmpty || name.unicodeScalars.contains(where: { forbidden.contains($0) })
            || name.first == "." || name.first == " " || name.last == "." || name.last == " "
        {
            problems.append(.invalidName(name))
        }
        if name.utf8.count > 255 { problems.append(.nameTooLong(name)) }
        return problems
    }

    static func key(_ url: URL) -> String {
        PhotoFilePath.canonical(url).lowercased()
    }

    private static func stemKey(folder: URL, stem: String) -> String {
        key(folder) + "/" + stem.lowercased()
    }

    private static func isInside(_ folder: URL, root: URL) -> Bool {
        let path = PhotoFilePath.canonical(folder)
        let rootPath = PhotoFilePath.canonical(root)
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func dateText(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
