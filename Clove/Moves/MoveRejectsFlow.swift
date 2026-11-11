import CloveCore
import Foundation
import Observation

/// The Move rejects sheet's state: plan, staged keeps, move and progress (PRD P0-10).
///
/// The flow reads every value through ``BrowsingModel``, so the sheet never reaches into the
/// library, the scan or a file path. The configuration is passed in at plan time, because PRD
/// Move rejects lets the folder name change in Settings and the move must use the name in force
/// when the user confirms. A keep is staged only: dismissing the sheet discards it, and the kept
/// photos' Reject is cleared only when Move runs.
@MainActor
@Observable
final class MoveRejectsFlow: Identifiable {
    /// What the sheet shows at one moment (PRD P0-10).
    enum Stage: Equatable {
        /// The plan is being built; nothing has moved.
        case planning
        /// The plan is ready and waits for the user's confirmation.
        case confirming(RejectMovePlan)
        /// The run is clearing kept rejects or moving sets, with its finished count and total.
        case moving(finished: Int, total: Int)
        /// The request failed as a whole, with no per-photo result to show.
        case failed(String)
        /// PRD Failure and recovery's read-only location copy.
        case readOnly
        /// The setting was turned off before the request reached the library.
        case disabled
    }

    /// The sheet's identity, so a new toolbar tap starts a new flow.
    let id = UUID()

    /// The browsing state and the library calls this flow performs.
    private let browsing: BrowsingModel

    /// What the sheet shows now.
    private(set) var stage: Stage = .planning

    /// The staged keeps for the plan, or nil before one is built (PRD P0-10).
    private(set) var keepSelection: RejectMoveKeepSelection?

    /// The folder open that produced the confirmation (PRD P0-02, P0-10).
    ///
    /// A reopen, even of the same folder, gets a new generation; a confirmation from an older
    /// open must never clear Reject or move files in the new one.
    private var confirmationContext: FolderContext?

    /// The thumbnails the keep grid draws for the open folder (PRD P0-10, P0-03).
    var thumbnails: any GridThumbnailSource { browsing.thumbnails }

    /// The task reading C6's progress stream (PRD P0-10).
    private var progressTask: Task<Void, Never>?

    /// Creates one sheet's flow over the scene's browsing model.
    init(browsing: BrowsingModel) {
        self.browsing = browsing
    }

    /// Plans the move once the sheet appears (PRD P0-10).
    ///
    /// A plan is built only from the `.planning` stage, so a returning view does not rebuild a
    /// confirmation the user is looking at.
    func planIfNeeded(configuration: RejectMoveConfiguration) async {
        guard stage == .planning else { return }
        await plan(configuration: configuration)
    }

    /// Builds the confirmation plan for the open folder's rejected photos (PRD P0-10).
    func plan(configuration: RejectMoveConfiguration) async {
        let context = FolderContext(browsing: browsing)
        stage = .planning
        do {
            let plan = try await browsing.planRejectMove(configuration: configuration)
            guard context.isCurrent(browsing) else {
                stage = .failed("The folder changed while preparing the move.")
                return
            }
            confirmationContext = context
            keepSelection = RejectMoveKeepSelection(plan: plan)
            stage = .confirming(plan)
        } catch let refusal as RejectMoveRefusal {
            stage = Self.stage(for: refusal)
        } catch {
            stage = .failed("The rejected photos couldn't be listed.")
        }
    }

    /// Keeps one ready set, or un-keeps it when it is already kept (design handoff, P0-10).
    func toggleKeep(_ identity: PhotoIdentity) {
        keepSelection?.toggle(identity)
    }

    /// Clears the kept photos' Reject, then moves the rest (design handoff, PRD P0-10).
    ///
    /// The keeps are staged until this call: every kept photo first goes through C4's existing
    /// mark path and gets the rating 0, which clears Reject and leaves the label untouched. Every
    /// kept photo is left out of the plan even when that clear fails. The plan's remaining sets then move
    /// through C6. A completed run is recorded on the model for the toast and C14's undo; the
    /// return value tells the sheet whether it can dismiss.
    func move(_ plan: RejectMovePlan) async -> Bool {
        // The stage becomes moving synchronously before the first await, so a second tap on Move
        // cannot start a second run or overwrite the completed move (PRD P0-10).
        guard case .confirming(let confirmed) = stage else { return false }
        guard confirmed == plan, let selection = keepSelection,
            let context = confirmationContext, context.isCurrent(browsing)
        else {
            stage = .failed("The folder changed before the move started.")
            return false
        }
        let kept = selection.orderedKeptIdentities
        let moving = selection.movingPlan
        stage = .moving(finished: 0, total: moving.photoCount)

        var clearing = RejectMoveKeepClearing()
        for identity in kept {
            guard context.isCurrent(browsing) else { return true }
            let status = await browsing.apply(.rating(.unrated), to: identity)
            clearing.record(
                status, for: identity,
                files: plan.readyEntries.first { $0.identity == identity }?.files ?? [])
        }
        guard context.isCurrent(browsing) else { return true }

        let progress = await browsing.rejectMoveProgress()
        guard context.isCurrent(browsing) else { return true }
        startProgress(progress)
        do {
            let result = try await browsing.runRejectMove(moving)
            await finishProgress()
            let outcomes =
                result.outcomes + clearing.clearFailures.map(RejectMoveOutcome.failed)
            let completed = RejectMoveResult(id: result.id, outcomes: outcomes)
            // A folder replaced while the move ran must not record its result against the new
            // one; the model already cleared the old record when that open happened.
            guard context.isCurrent(browsing) else { return true }
            browsing.recordRejectMove(
                completed, keptIdentities: kept,
                rejectsFolderName: plan.configuration.rejectsFolderName,
                folder: context.folder, openGeneration: context.generation)
            return true
        } catch let refusal as RejectMoveRefusal {
            cancelProgress()
            // Nothing moved, so the keep clears are restored; a whole-request refusal must not
            // leave the kept photos changed without a completed record C14 can undo.
            if context.isCurrent(browsing) {
                await restore(clearing.restorationIdentities, context: context)
            }
            stage = Self.stage(for: refusal)
            return false
        } catch {
            cancelProgress()
            if context.isCurrent(browsing) {
                await restore(clearing.restorationIdentities, context: context)
            }
            stage = .failed("The rejected photos couldn't be moved.")
            return false
        }
    }

    /// Restores Reject on kept photos whose clear ran before a whole-request failure (P0-10).
    private func restore(_ identities: [PhotoIdentity], context: FolderContext) async {
        for identity in identities {
            guard context.isCurrent(browsing) else { return }
            _ = await browsing.apply(.rating(.rejected), to: identity)
        }
    }

    /// The folder open a confirmation belongs to (PRD P0-02, P0-10).
    @MainActor
    private struct FolderContext: Equatable {
        let folder: FolderIdentity?
        let generation: Int

        init(browsing: BrowsingModel) {
            folder = browsing.state.folder
            generation = browsing.openGeneration
        }

        func isCurrent(_ browsing: BrowsingModel) -> Bool {
            browsing.state.folder == folder && browsing.openGeneration == generation
        }
    }

    /// Subscribes to C6's progress before a run starts (PRD P0-10).
    ///
    /// The stream is created before the run, so every step is buffered even when the consumer
    /// task has not started iterating yet; a short move therefore still reports its finish.
    private func startProgress(_ stream: AsyncStream<RejectMoveProgress>) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            for await update in stream {
                guard let self, !Task.isCancelled else { return }
                switch update {
                case .setStarted:
                    break
                case .setFinished:
                    guard case .moving(let finished, let total) = self.stage else { continue }
                    self.stage = .moving(finished: min(finished + 1, total), total: total)
                case .finished:
                    return
                }
            }
        }
    }

    /// Waits for the progress stream to see the run's final step (PRD P0-10).
    private func finishProgress() async {
        await progressTask?.value
        progressTask = nil
    }

    /// Stops reading progress after a run failed before it finished (PRD P0-10).
    private func cancelProgress() {
        progressTask?.cancel()
        progressTask = nil
    }

    /// Maps a whole-request refusal to the sheet's copy (PRD P0-10, Failure and recovery).
    private static func stage(for refusal: RejectMoveRefusal) -> Stage {
        switch refusal {
        case .disabled: .disabled
        case .readOnlyLocation: .readOnly
        case .undone: .failed("This move was undone.")
        }
    }
}
