import CloveCore
import Foundation
import Observation

struct RenameOptions: Hashable {
    var prefix = ""
    var start = 1
    var digits = 3
    var addsCaptureDate = false
    var movesToFolder = false
    var folderName = ""

    var template: RenameTemplate {
        RenameTemplate(
            prefix: prefix, sequenceStart: start, digits: digits,
            includesCaptureDate: addsCaptureDate)
    }
    var destination: RenameDestination { movesToFolder ? .folder(folderName) : .inPlace }
}

/// Only this presentation owns the order and naming choices. Cancel discards them.
@MainActor
@Observable
final class BatchRenameFlow: Identifiable {
    let id = UUID()
    let browsing: BrowsingModel
    private let folder: FolderIdentity?
    private let generation: Int
    private(set) var order: [GridPhoto]
    var options = RenameOptions()
    private(set) var preview: BatchRenamePlan?
    private(set) var message: String?
    private(set) var isRunning = false
    private(set) var finishedCount = 0
    private var previewOptions: RenameOptions?

    init(browsing: BrowsingModel) {
        self.browsing = browsing
        folder = browsing.state.folder
        generation = browsing.openGeneration
        order = browsing.batchTargets
    }

    func move(_ photo: PhotoIdentity, to position: Int) {
        guard !isRunning, let index = order.firstIndex(where: { $0.id == photo }),
            order.indices.contains(position), index != position
        else { return }
        order.insert(order.remove(at: index), at: position)
        preview = nil
    }

    func prepare(rejectsFolderName: RejectsFolderName) async {
        guard !isRunning else { return }
        let requested = options
        preview = nil
        previewOptions = nil
        message = nil
        do {
            try checkFolder()
            let plan = try await browsing.planBatchRename(
                order: order.map(\.id), template: requested.template,
                destination: requested.destination, rejectsFolderName: rejectsFolderName)
            guard !Task.isCancelled, requested == options else { return }
            try checkFolder()
            preview = plan
            previewOptions = requested
        } catch {
            guard !Task.isCancelled, requested == options else { return }
            message = error.localizedDescription
        }
    }

    var canRename: Bool {
        !isRunning && browsing.canMark && !order.isEmpty && preview?.canRename == true
            && previewOptions == options
    }

    func rename(completion: @escaping () -> Void) async {
        guard canRename, let plan = preview else { return }
        do { try checkFolder() } catch {
            message = error.localizedDescription
            return
        }
        isRunning = true
        finishedCount = 0
        message = nil
        do {
            try await browsing.runBatchRename(plan) { [weak self] update in
                if case .setFinished(_, pass: .finalName) = update {
                    self?.finishedCount += 1
                }
            }
            completion()
        } catch let BatchRenameRefusal.problems(plan) {
            preview = plan
            message = "The files changed. Review the preview before renaming."
        } catch {
            message = error.localizedDescription
        }
        isRunning = false
    }

    private func checkFolder() throws {
        guard folder == browsing.state.folder, generation == browsing.openGeneration else {
            throw RenameFlowError.folderChanged
        }
    }
}

enum RenameFlowError: LocalizedError {
    case folderChanged
    case unavailable
    case photoMissing
    case rescanFailed

    var errorDescription: String? {
        switch self {
        case .folderChanged: "The folder changed. Cancel and select the photos again."
        case .unavailable: "This folder can't be renamed right now."
        case .photoMissing: "A selected photo is no longer in this folder."
        case .rescanFailed: "The renamed folder couldn't be read again. Reopen the folder."
        }
    }
}

extension RenameProblem {
    var explanation: String {
        explanation(language: .english)
    }

    func explanation(language: ResolvedAppLanguage) -> String {
        switch self {
        case .invalidName:
            AppLocalization.string(
                "The name contains an invalid character or starts or ends with a dot or space.",
                language: language)
        case .nameTooLong:
            AppLocalization.string("The filename is over 255 bytes.", language: language)
        case .invalidSequence:
            AppLocalization.string(
                "Use a nonnegative start number and 1–255 digits.", language: language)
        case .sequenceOverflow:
            AppLocalization.string("The sequence number is too large.", language: language)
        case .dateUnavailable:
            AppLocalization.string(
                "No capture date or file creation date is available.", language: language)
        case .destinationIsFile:
            AppLocalization.string(
                "The destination name belongs to a file.", language: language)
        case .rejectsDestination:
            AppLocalization.string(
                "Choose a folder other than the rejects folder.", language: language)
        case .duplicateTarget:
            AppLocalization.string(
                "Two photos in this batch would have the same name.", language: language)
        case .duplicateSource:
            AppLocalization.string("This photo appears twice in the batch.", language: language)
        case .ambiguousSidecar:
            AppLocalization.string("More than one sidecar matches this photo.", language: language)
        case .outsideOpenedFolder:
            AppLocalization.string(
                "The photo or destination is outside the opened folder.", language: language)
        case .fileSystem(let reason):
            AppLocalization.format("The folder couldn't be read: %@", language: language, reason)
        }
    }
}

/// The result supplies confirmed final moves, plus any sets left under temporary names.
struct CompletedBatchRename {
    let plan: BatchRenamePlan
    let result: BatchRenameResult
    var rescanFailure: String?

    var message: String {
        if result.failure == nil {
            return result.renamedCount == 1
                ? "Renamed 1 photo" : "Renamed \(result.renamedCount) photos"
        }
        return "Renamed \(result.renamedCount) of \(plan.rows.count)"
    }
    var detail: String? { result.failure?.message ?? rescanFailure }
    var hasDetails: Bool {
        result.failure != nil || !result.temporarySets.isEmpty || rescanFailure != nil
    }

    func localizedMessage(language: ResolvedAppLanguage) -> String {
        if result.failure == nil {
            return AppLocalization.format(
                "Renamed %lld photos", language: language, Int64(result.renamedCount))
        }
        return AppLocalization.format(
            "Renamed %lld of %lld", language: language, Int64(result.renamedCount),
            Int64(plan.rows.count))
    }

    func localizedDetail(language: ResolvedAppLanguage) -> String? {
        if let message = result.failure?.message { return message }
        return rescanFailure.map { AppLocalization.string($0, language: language) }
    }

    func newIdentity(for original: PhotoIdentity) -> PhotoIdentity {
        if let temporary = result.temporarySets.first(where: { $0.identity == original }) {
            return PhotoIdentity(
                folderID: original.folderID, relativeFolderPath: original.relativeFolderPath,
                stem: temporary.stem)
        }
        let changed = plan.rows.filter { !$0.isNoOp }.prefix(result.renamedCount)
        guard let row = changed.first(where: { $0.id == original }) else { return original }
        return PhotoIdentity(
            folderID: original.folderID, relativeFolderPath: row.destinationRelativeFolder,
            stem: row.newStem)
    }
}
