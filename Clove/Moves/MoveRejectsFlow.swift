import CloveCore
import Foundation
import Observation

/// The sheet previews counts and stages keeps. Confirming submits both operations synchronously;
/// the browsing model owns their ordered execution and replans against the files at run time.
@MainActor
@Observable
final class MoveRejectsFlow: Identifiable {
    enum Stage: Equatable {
        case planning
        case confirming(RejectMovePlan)
        case moving(finished: Int, total: Int)
        case failed(String)
        case readOnly
        case disabled
    }

    let id = UUID()
    private let browsing: BrowsingModel
    private(set) var stage: Stage = .planning
    private(set) var keepSelection: RejectMoveKeepSelection?
    private var confirmationFolder: FolderIdentity?
    private var confirmationGeneration: Int?

    var thumbnails: any GridThumbnailSource { browsing.thumbnails }

    init(browsing: BrowsingModel) { self.browsing = browsing }

    func planIfNeeded(configuration: RejectMoveConfiguration) async {
        guard stage == .planning else { return }
        await plan(configuration: configuration)
    }

    func plan(configuration: RejectMoveConfiguration) async {
        let folder = browsing.state.folder
        let generation = browsing.openGeneration
        stage = .planning
        do {
            let plan = try await browsing.planRejectMove(configuration: configuration)
            guard folder == browsing.state.folder, generation == browsing.openGeneration else {
                stage = .failed("The folder changed while preparing the move.")
                return
            }
            confirmationFolder = folder
            confirmationGeneration = generation
            keepSelection = RejectMoveKeepSelection(plan: plan)
            stage = .confirming(plan)
        } catch let refusal as RejectMoveRefusal {
            stage = Self.stage(for: refusal)
        } catch {
            stage = .failed("The rejected photos couldn't be listed.")
        }
    }

    func toggleKeep(_ identity: PhotoIdentity) { keepSelection?.toggle(identity) }

    func move(_ plan: RejectMovePlan, completion: @escaping () -> Void) {
        guard case .confirming(let confirmed) = stage, confirmed == plan,
            let selection = keepSelection
        else { return }
        guard confirmationFolder == browsing.state.folder,
            confirmationGeneration == browsing.openGeneration
        else {
            stage = .failed("The folder changed before the move started.")
            return
        }
        stage = .moving(finished: 0, total: selection.movingPlan.photoCount)
        browsing.runRejectMove(plan, kept: selection.orderedKeptIdentities) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                completion()
            case .failure(let refusal as RejectMoveRefusal):
                self.stage = Self.stage(for: refusal)
            case .failure:
                self.stage = .failed("The rejected photos couldn't be moved.")
            }
        }
    }

    private static func stage(for refusal: RejectMoveRefusal) -> Stage {
        switch refusal {
        case .disabled: .disabled
        case .readOnlyLocation: .readOnly
        case .undone: .failed("This move was undone.")
        }
    }
}
