import CloveCore
import CoreGraphics
import SwiftUI

/// Confirmation sheet for moving rejected photos.
struct MoveRejectsSheet: View {
    let flow: MoveRejectsFlow
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .presentationBackground(Color.clove.surface.sheet)
            .presentationDetents([.height(330), .large])
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
            ProgressView(AppLocalization.string("Preparing…", language: language))
                .accessibilityIdentifier("clove.moves.preparing")
        case .confirming(let plan):
            confirmation(plan)
        case .moving(let finished, let total):
            VStack(spacing: 16) {
                ProgressView(value: Double(finished), total: Double(max(total, 1)))
                Text(
                    total == 1
                        ? AppLocalization.string("Moving 1 photo", language: language)
                        : AppLocalization.format(
                            "Moving %lld of %lld photos", language: language,
                            Int64(min(finished + 1, total)), Int64(total))
                )
                .accessibilityIdentifier("clove.moves.progress")
            }
        case .failed(let message):
            failure(AppLocalization.string(message, language: language), identifier: "failure")
        case .readOnly:
            failure(
                AppLocalization.string(RejectMoveCopy.viewOnlyLocation, language: language),
                identifier: "viewOnly")
        case .disabled:
            failure(
                AppLocalization.string("Move rejects is turned off.", language: language),
                identifier: "disabled")
        }
    }

    private func confirmation(_ plan: RejectMovePlan) -> some View {
        let title = AppLocalization.format(
            "Move %lld rejected photos", language: language, Int64(plan.photoCount))
        let bodyText = AppLocalization.format(
            "To %@ in this folder. Nothing is deleted.", language: language,
            plan.configuration.rejectsFolderName.rawValue)
        let refusedMessage: String? =
            plan.refusedCount == 0
            ? nil
            : AppLocalization.format(
                "%lld photos can't be moved right now.", language: language,
                Int64(plan.refusedCount))
        return VStack(spacing: 16) {
            fannedStack(plan)
            Text(title)
                .font(.title3.bold())
                .accessibilityIdentifier("clove.moves.confirmation")
                .reportHeaderControlFrame("clove.moves.confirmation")
            Text(bodyText)
                .font(.footnote)
                .foregroundStyle(Color.clove.text.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("clove.moves.body")
            if let refused = refusedMessage {
                Text(refused).font(.footnote).foregroundStyle(Color.clove.reject)
                    .accessibilityIdentifier("clove.moves.refused")
            }
            Button(AppLocalization.string("Move", language: language)) {
                flow.move(plan) { dismiss() }
            }
            .buttonStyle(MoveSheetButtonStyle())
            .disabled(plan.photoCount == 0)
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

    private func failure(_ message: String, identifier: String) -> some View {
        VStack(spacing: 20) {
            Text(message).accessibilityIdentifier("clove.moves.\(identifier)")
            Button(AppLocalization.string("Cancel", language: language), role: .cancel) {
                dismiss()
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(secondary ? Color.clove.accent : primaryForeground)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(secondary ? Color.clove.surface.card : Color.clove.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(
                CloveMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
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

    init(photo: PhotoIdentity, source: any GridThumbnailSource) {
        self.photo = photo
        self.source = source
        if case .image(let cached) = source.cachedThumbnail(for: photo) {
            _image = State(initialValue: cached)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.clove.surface.card)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .task(id: photo) {
            if case .image(let cached) = source.cachedThumbnail(for: photo) {
                image = cached
                return
            }
            image = nil
            if case .image(let loaded) = await source.thumbnail(for: photo, priority: .visible) {
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
        .accessibilityHidden(true)
    }
}
