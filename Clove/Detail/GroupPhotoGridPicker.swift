import CloveCore
import SwiftUI

/// Adaptive presentation style for ``GroupPhotoGridPicker``, matching Clove's regular-popover /
/// compact-sheet convention.
enum GroupPhotoGridPickerPresentationMode: Equatable, Sendable {
    case popover
    case sheet

    static func resolved(horizontalSizeClass: UserInterfaceSizeClass?) -> Self {
        horizontalSizeClass == .regular ? .popover : .sheet
    }
}

/// Multi-column grid picker showing every visible member of the expanded group so long bursts can
/// be scanned at a glance and jumped to in one tap.
struct GroupPhotoGridPicker: View {
    let group: ActiveBrowsingGroup
    let current: PhotoIdentity?
    let thumbnails: any GridThumbnailSource
    let showsDoneButton: Bool
    let onSelect: (PhotoIdentity) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.appLanguage) private var language

    static let popoverWidth: CGFloat = 444
    static let popoverColumns = 3
    static let gridPadding: CGFloat = 12
    static let gridSpacing: CGFloat = 4

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Self.gridSpacing),
            count: Self.popoverColumns
        )
    }

    private var countText: String {
        AppLocalization.format(
            "%lld photos", language: language, Int64(group.visibleMembers.count))
    }

    static func popoverHeight(memberCount: Int, compactHeight: Bool) -> CGFloat {
        let rows = max(1, (max(memberCount, 1) + popoverColumns - 1) / popoverColumns)
        let innerWidth = popoverWidth - gridPadding * 2
        let cellSide =
            (innerWidth - CGFloat(popoverColumns - 1) * gridSpacing) / CGFloat(popoverColumns)
        let gridContentHeight =
            gridPadding * 2
            + CGFloat(rows) * cellSide
            + CGFloat(max(rows - 1, 0)) * gridSpacing
        let headerHeight: CGFloat = 41
        let maxAllowed: CGFloat = compactHeight ? 280 : 520
        return min(maxAllowed, max(142, headerHeight + gridContentHeight))
    }

    var body: some View {
        Group {
            if showsDoneButton {
                NavigationStack {
                    gridScrollView
                        .background(Color.clove.surface.sheet)
                        .navigationTitle(
                            AppLocalization.string("Similar group", language: language)
                        )
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                VStack(spacing: 1) {
                                    Text(
                                        AppLocalization.string("Similar group", language: language)
                                    )
                                    .font(.headline)
                                    .lineLimit(1)
                                    Text(countText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Color.clove.text.secondary)
                                        .lineLimit(1)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("clove.detail.groupPicker.count")
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(AppLocalization.string("Done", language: language)) {
                                    dismiss()
                                }
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.clove.accent)
                                .accessibilityIdentifier("clove.detail.groupPicker.done")
                            }
                        }
                }
                .background(Color.clove.surface.sheet)
                .presentationBackground(Color.clove.surface.sheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(AppLocalization.string("Similar group", language: language))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(countText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.clove.text.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("clove.detail.groupPicker.count")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    Divider().overlay(Color.clove.separator)
                    gridScrollView
                }
                .frame(
                    width: Self.popoverWidth,
                    height: Self.popoverHeight(
                        memberCount: group.visibleMembers.count,
                        compactHeight: verticalSizeClass == .compact)
                )
                .background(Color.clove.surface.sheet)
                .presentationBackground(Color.clove.surface.sheet)
            }
        }
        .foregroundStyle(Color.clove.text.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.groupPicker")
    }

    private var gridScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                    ForEach(group.visibleMembers) { photo in
                        let isCurrent = photo.id == current
                        Button {
                            onSelect(photo.id)
                            dismiss()
                        } label: {
                            GroupPhotoGridPickerCell(
                                photo: photo,
                                isCurrent: isCurrent,
                                thumbnails: thumbnails)
                        }
                        .buttonStyle(.plain)
                        .id(photo.id)
                        .accessibilityLabel(photo.fileName)
                        .accessibilityValue(MarkSummary.text(for: photo.marks, language: language))
                        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                        .accessibilityIdentifier(
                            "clove.detail.groupPicker.photo.\(photo.id.stem.lowercased())")
                    }
                }
                .padding(Self.gridPadding)
            }
            .onAppear {
                scrollToCurrent(using: proxy)
            }
            .task(id: group.id) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                scrollToCurrent(using: proxy)
            }
        }
    }

    private func scrollToCurrent(using proxy: ScrollViewProxy) {
        guard let current,
            group.visibleMembers.contains(where: { $0.id == current })
        else { return }
        proxy.scrollTo(current, anchor: .center)
    }
}

private struct GroupPhotoGridPickerCell: View {
    let photo: GridPhoto
    let isCurrent: Bool
    let thumbnails: any GridThumbnailSource

    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @State private var thumbnail: CGImage?
    @State private var isUnavailable = false

    init(
        photo: GridPhoto,
        isCurrent: Bool,
        thumbnails: any GridThumbnailSource
    ) {
        self.photo = photo
        self.isCurrent = isCurrent
        self.thumbnails = thumbnails
        if case .image(let cached) = thumbnails.cachedThumbnail(for: photo.id) {
            _thumbnail = State(initialValue: cached)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else if isUnavailable {
                    VStack(spacing: 2) {
                        Text((photo.fileName as NSString).pathExtension.uppercased())
                            .font(.caption2.weight(.semibold))
                        Text(AppLocalization.string("No preview", language: language))
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.clove.text.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clove.surface.card)
                } else {
                    Rectangle().fill(Color.clove.surface.card)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                PhotoTileRatingBadge(rating: photo.marks.rating)
            }
            .overlay(alignment: .bottomTrailing) {
                PhotoTileLabelDot(label: photo.marks.label)
            }
            .opacity(photo.marks.isRejected ? theme.tokens.rejectedOpacity : 1)
            .overlay {
                if isCurrent {
                    CurrentPhotoIndicator(cornerRadius: 6)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: photo.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if case .image(let cached) = thumbnails.cachedThumbnail(for: photo.id) {
            thumbnail = cached
            isUnavailable = false
            return
        }
        for delay in [0, 150, 300, 600, 1_200, 2_400] {
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard !Task.isCancelled else { return }
            switch await thumbnails.thumbnail(for: photo.id, priority: .visible) {
            case .image(let pixels):
                thumbnail = pixels
                isUnavailable = false
                return
            case .unavailable:
                isUnavailable = true
                return
            case .deferred:
                continue
            }
        }
    }
}
