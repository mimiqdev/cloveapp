import CloveCore
import CoreGraphics
import SwiftUI

/// Confirmation stages keeps locally. Only Move submits them to the ordered action pipeline.
struct MoveRejectsSheet: View {
    let flow: MoveRejectsFlow
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @State private var expanded = false
    @State private var detent: PresentationDetent = .height(330)

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .presentationBackground(Color.clove.surface.sheet)
            .presentationDetents([.height(330), .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(isMoving)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clove.moves.sheet")
            .task {
                await flow.planIfNeeded(
                    configuration: RejectMoveConfiguration(settings: store.settings))
            }
    }

    @ViewBuilder private var content: some View {
        switch flow.stage {
        case .planning:
            ProgressView("Preparing…").accessibilityIdentifier("clove.moves.preparing")
        case .confirming(let plan):
            confirmation(plan)
        case .moving(let finished, let total):
            VStack(spacing: 16) {
                ProgressView(value: Double(finished), total: Double(max(total, 1)))
                    .tint(Color.clove.accent)
                Text(
                    total == 0
                        ? "Clearing kept rejects"
                        : "Moving \(min(finished + 1, total)) of \(total) photos"
                )
                .accessibilityIdentifier("clove.moves.progress")
            }
        case .failed(let message): failure(message, identifier: "failure")
        case .readOnly: failure(RejectMoveCopy.viewOnlyLocation, identifier: "viewOnly")
        case .disabled: failure("Move rejects is turned off.", identifier: "disabled")
        }
    }

    private func confirmation(_ plan: RejectMovePlan) -> some View {
        let selection = flow.keepSelection ?? RejectMoveKeepSelection(plan: plan)
        let copy = RejectMoveConfirmation(selection: selection)
        return VStack(spacing: 16) {
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "\(selection.movingCount.formatted()) of \(selection.totalCount.formatted()) will move"
                    )
                    .font(.headline)
                    .accessibilityIdentifier("clove.moves.partial")
                    Text("Tap a photo to keep it.")
                        .font(.footnote).foregroundStyle(Color.clove.text.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ScrollView { keepGrid(plan, selection: selection) }
                    .accessibilityIdentifier("clove.moves.keepGrid")
            } else {
                Button {
                    expanded = true
                    detent = .large
                } label: {
                    fannedStack(plan)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review rejected photos")
                .accessibilityHint("Opens the grid. Tap a photo to keep it.")
                .accessibilityIdentifier("clove.moves.expand")
                Text(copy.title)
                    .font(.title3.bold())
                    .accessibilityIdentifier("clove.moves.confirmation")
                Text(copy.body)
                    .font(.footnote)
                    .foregroundStyle(Color.clove.text.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("clove.moves.body")
            }
            if let refused = copy.refusedMessage {
                Text(refused).font(.footnote).foregroundStyle(Color.clove.reject)
                    .accessibilityIdentifier("clove.moves.refused")
            }
            Button(expanded ? "Move \(selection.movingCount.formatted())" : copy.moveButtonTitle) {
                flow.move(plan) { dismiss() }
            }
            .buttonStyle(MoveSheetButtonStyle())
            .disabled(selection.movingCount == 0)
            .accessibilityIdentifier("clove.moves.confirm")
        }
    }

    private func fannedStack(_ plan: RejectMovePlan) -> some View {
        let entries = Array(plan.readyEntries.prefix(4))
        return ZStack {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                MoveRejectsThumbnail(photo: entry.identity, source: flow.thumbnails)
                    .frame(width: 72, height: 96)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).stroke(
                            Color.clove.bg.canvas, lineWidth: 2)
                    }
                    .rotationEffect(.degrees(Double(index) * 9 - 14))
                    .offset(
                        x: CGFloat(index) * 20 - CGFloat(entries.count - 1) * 10,
                        y: CGFloat(index) * 3)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func keepGrid(_ plan: RejectMovePlan, selection: RejectMoveKeepSelection) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4
        ) {
            ForEach(plan.readyEntries) { entry in
                let kept = selection.isKept(entry.identity)
                Button {
                    flow.toggleKeep(entry.identity)
                } label: {
                    MoveRejectsThumbnail(photo: entry.identity, source: flow.thumbnails)
                        .aspectRatio(1, contentMode: .fit)
                        .opacity(kept ? 1 : theme.tokens.rejectedOpacity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    entry.files.first(where: { $0.role == .primary })?.source.lastPathComponent
                        ?? entry.identity.stem
                )
                .accessibilityValue(kept ? "Kept" : "Will move")
                .accessibilityIdentifier("clove.moves.keep.\(entry.identity.stem)")
            }
        }
    }

    private func failure(_ message: String, identifier: String) -> some View {
        VStack(spacing: 20) {
            Text(message).accessibilityIdentifier("clove.moves.\(identifier)")
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(MoveSheetButtonStyle())
                .accessibilityIdentifier("clove.moves.cancel")
        }
    }

    private var isMoving: Bool {
        if case .moving = flow.stage { return true }
        return false
    }
}

/// The full-width action shared by the confirmation and failure-details sheets.
struct MoveSheetButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.cloveTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(secondary ? Color.clove.accent : primaryForeground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(secondary ? Color.clove.surface.card : Color.clove.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var primaryForeground: CloveColour {
        theme.appearance == .dark ? Color.clove.text.primary : Color.clove.bg.canvas
    }
}

/// Aspect-fill pixels from the browsing thumbnail source; no file access or tinting here.
struct MoveRejectsThumbnail: View {
    let photo: PhotoIdentity
    let source: any GridThumbnailSource
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(Color.clove.surface.card)
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .task(id: photo) {
            image = nil
            if case .image(let loaded) = await source.thumbnail(for: photo, priority: .visible) {
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
        .accessibilityHidden(true)
    }
}
