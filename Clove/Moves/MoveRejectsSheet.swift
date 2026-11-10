import CloveCore
import CoreGraphics
import SwiftUI

/// The Move rejects sheet: confirmation with staged keeps, progress and whole-request failures.
///
/// The design handoff's "Move Rejects" copy supplies the title, destination and no-delete promise;
/// ``RejectMoveConfirmation`` narrows them to the plan and the staged keeps. The sheet reads the
/// settings store when it plans, so a folder renamed in Settings is the destination the next run
/// uses (PRD Move rejects, C12). A keep is only staged here; dismissing the sheet discards it.
///
/// Design placeholder: system text, buttons, a progress view and a thumbnail grid stand in for
/// the handoff's glass sheet and fanned stack.
struct MoveRejectsSheet: View {
    /// The sheet's plan, staged keeps and progress state.
    let flow: MoveRejectsFlow

    /// The app-wide settings, read live for the rejects folder name (PRD Move rejects).
    @Environment(SettingsStore.self) private var store

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .interactiveDismissDisabled(isMoving)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.moves.sheet")
        .task {
            await flow.planIfNeeded(configuration: configuration)
        }
    }

    /// The stage the sheet shows now (PRD P0-10).
    @ViewBuilder
    private var content: some View {
        switch flow.stage {
        case .planning:
            ProgressView("Preparing…")
                .accessibilityIdentifier("clove.moves.preparing")
        case .confirming(let plan):
            confirmation(plan)
        case .moving(let finished, let total):
            moving(finished: finished, total: total)
        case .failed(let message):
            failure(message)
        case .readOnly:
            viewOnly
        case .disabled:
            disabled
        }
    }

    /// The handoff's confirm sheet: title, destination, keep grid, count and Move (P0-10).
    @ViewBuilder
    private func confirmation(_ plan: RejectMovePlan) -> some View {
        let selection = flow.keepSelection ?? RejectMoveKeepSelection(plan: plan)
        let copy = RejectMoveConfirmation(selection: selection)
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.title)
                .font(.title2.bold())
                .accessibilityIdentifier("clove.moves.confirmation")
            Text(copy.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("clove.moves.body")
            if let refused = copy.refusedMessage {
                Text(refused)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clove.moves.refused")
            }
            Text("Tap a photo to keep it.")
                .font(.callout)
                .accessibilityIdentifier("clove.moves.keepHint")
            keepGrid(plan, selection: selection)
            if let partial = copy.partialLine {
                Text(partial)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("clove.moves.partial")
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .accessibilityIdentifier("clove.moves.cancel")
                Spacer()
                Button(copy.moveButtonTitle) {
                    Task {
                        if await flow.move(plan) { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("clove.moves.confirm")
            }
        }
    }

    /// The rejects as tappable thumbnails; a kept photo returns to full brightness (P0-10).
    @ViewBuilder
    private func keepGrid(
        _ plan: RejectMovePlan, selection: RejectMoveKeepSelection
    ) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 6), count: 4)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(plan.readyEntries) { entry in
                let kept = selection.isKept(entry.identity)
                Button {
                    flow.toggleKeep(entry.identity)
                } label: {
                    MoveRejectsThumbnail(
                        photo: entry.identity, source: flow.thumbnails
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(kept ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.fileName(of: entry))
                .accessibilityValue(kept ? "Kept" : "Will move")
                .accessibilityIdentifier("clove.moves.keep.\(entry.identity.stem)")
            }
        }
        .accessibilityIdentifier("clove.moves.keepGrid")
    }

    /// The count PRD P0-10 asks for while the move runs.
    @ViewBuilder
    private func moving(finished: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if total == 0 {
                ProgressView()
                Text("Clearing kept rejects")
                    .accessibilityIdentifier("clove.moves.progress")
            } else {
                ProgressView(value: Double(finished), total: Double(total))
                Text(
                    total == 1
                        ? "Moving 1 photo"
                        : "Moving \(min(finished + 1, total)) of \(total) photos"
                )
                .accessibilityIdentifier("clove.moves.progress")
            }
        }
    }

    /// A whole-request failure with nothing per photo to report (PRD Failure and recovery).
    @ViewBuilder
    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .accessibilityIdentifier("clove.moves.failure")
            Button("Cancel", role: .cancel) { dismiss() }
                .accessibilityIdentifier("clove.moves.cancel")
        }
    }

    /// PRD Failure and recovery's read-only sentence, kept in CloveCore (P0-10).
    @ViewBuilder
    private var viewOnly: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(RejectMoveCopy.viewOnlyLocation)
                .accessibilityIdentifier("clove.moves.viewOnly")
            Button("Cancel", role: .cancel) { dismiss() }
                .accessibilityIdentifier("clove.moves.cancel")
        }
    }

    /// A setting that was turned off before the request reached the library (PRD Move rejects).
    @ViewBuilder
    private var disabled: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move rejects is turned off.")
                .accessibilityIdentifier("clove.moves.disabled")
            Button("Cancel", role: .cancel) { dismiss() }
                .accessibilityIdentifier("clove.moves.cancel")
        }
    }

    /// Whether a run is in progress, so the sheet cannot be swiped away mid-move (PRD P0-10).
    private var isMoving: Bool {
        if case .moving = flow.stage { return true }
        return false
    }

    /// The settings value read when the sheet plans (PRD Move rejects).
    private var configuration: RejectMoveConfiguration {
        RejectMoveConfiguration(settings: store.settings)
    }

    /// A set's primary file name, for a keep tile's accessibility label (PRD P0-10).
    private static func fileName(of entry: RejectMoveSetPlan) -> String {
        entry.files.first(where: { $0.role == .primary })?.source.lastPathComponent
            ?? entry.identity.stem
    }
}

/// One keep tile's thumbnail, read through the grid's source for the open folder (PRD P0-03).
///
/// The tile is only a placeholder: the handoff's thumbnails arrive with Q6's visual pass.
/// Design placeholder: a generated or pipeline preview inside a rounded system rectangle.
struct MoveRejectsThumbnail: View {
    /// The photo whose primary preview the tile shows (PRD P0-10).
    let photo: PhotoIdentity
    /// The open folder's grid thumbnail source (PRD P0-03).
    let source: any GridThumbnailSource

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task {
            guard image == nil else { return }
            if case .image(let loaded) = await source.thumbnail(
                for: photo, priority: .visible)
            {
                image = loaded
            }
        }
    }
}
