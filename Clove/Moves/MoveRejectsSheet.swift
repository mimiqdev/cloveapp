import CloveCore
import CoreGraphics
import SwiftUI

/// Confirmation stages keeps locally. Only Move submits them to the ordered action pipeline.
struct MoveRejectsSheet: View {
    let flow: MoveRejectsFlow
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @State private var expanded: Bool
    @State private var detent: PresentationDetent

    init(flow: MoveRejectsFlow, initiallyExpanded: Bool = false) {
        self.flow = flow
        _expanded = State(initialValue: initiallyExpanded)
        _detent = State(initialValue: initiallyExpanded ? .large : .height(330))
    }

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
            ProgressView(AppLocalization.string("Preparing…", language: language))
                .accessibilityIdentifier("clove.moves.preparing")
        case .confirming(let plan):
            confirmation(plan)
        case .moving(let finished, let total):
            VStack(spacing: 16) {
                ProgressView(value: Double(finished), total: Double(max(total, 1)))
                Text(
                    total == 0
                        ? AppLocalization.string("Clearing kept rejects", language: language)
                        : total == 1
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
        let selection = flow.keepSelection ?? RejectMoveKeepSelection(plan: plan)
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
        let moveButtonTitle =
            selection.movingCount == plan.photoCount
            ? AppLocalization.string("Move", language: language)
            : AppLocalization.format("Move %lld", language: language, Int64(selection.movingCount))
        return VStack(spacing: 16) {
            if expanded {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            AppLocalization.format(
                                "%lld of %lld will move", language: language,
                                Int64(selection.movingCount), Int64(selection.totalCount))
                        )
                        .font(.headline)
                        .accessibilityIdentifier("clove.moves.partial")
                        Text(AppLocalization.string("Tap a photo to keep it.", language: language))
                            .font(.footnote).foregroundStyle(Color.clove.text.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView { keepGrid(plan, selection: selection) }
                        .accessibilityIdentifier("clove.moves.keepGrid")
                }
                .transition(
                    .asymmetric(
                        insertion: CloveMotion.scaleOpacityTransition(
                            scale: 0.96, anchor: .center, reduceMotion: reduceMotion),
                        removal: .identity))
            } else {
                VStack(spacing: 16) {
                    Button {
                        withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                            expanded = true
                            detent = .large
                        }
                    } label: {
                        fannedStack(plan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        AppLocalization.string("Review rejected photos", language: language)
                    )
                    .accessibilityIdentifier("clove.moves.expand")
                    Text(title)
                        .font(.title3.bold())
                        .accessibilityIdentifier("clove.moves.confirmation")
                        .reportHeaderControlFrame("clove.moves.confirmation")
                    Text(bodyText)
                        .font(.footnote)
                        .foregroundStyle(Color.clove.text.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("clove.moves.body")
                }
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            if let refused = refusedMessage {
                Text(refused).font(.footnote).foregroundStyle(Color.clove.reject)
                    .accessibilityIdentifier("clove.moves.refused")
            }
            Button {
                flow.move(plan) { dismiss() }
            } label: {
                Text(
                    expanded
                        ? AppLocalization.format(
                            "Move %lld", language: language, Int64(selection.movingCount))
                        : moveButtonTitle
                )
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(
                    CloveMotion.micro(reduceMotion: reduceMotion), value: selection.movingCount
                )
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
                    withAnimation(CloveMotion.micro(reduceMotion: reduceMotion)) {
                        flow.toggleKeep(entry.identity)
                    }
                } label: {
                    MoveRejectsThumbnail(
                        photo: entry.identity,
                        source: flow.thumbnails,
                        isDimmed: !kept
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .animation(CloveMotion.micro(reduceMotion: reduceMotion), value: kept)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    entry.files.first(where: { $0.role == .primary })?.source.lastPathComponent
                        ?? entry.identity.stem
                )
                .accessibilityValue(
                    AppLocalization.string(kept ? "Kept" : "Will move", language: language)
                )
                .accessibilityIdentifier("clove.moves.keep.\(entry.identity.stem)")
            }
        }
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
    var isDimmed = false
    @State private var image: CGImage?

    init(photo: PhotoIdentity, source: any GridThumbnailSource, isDimmed: Bool = false) {
        self.photo = photo
        self.source = source
        self.isDimmed = isDimmed
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
            .rejectedThumbnailDimming(isDimmed)
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
