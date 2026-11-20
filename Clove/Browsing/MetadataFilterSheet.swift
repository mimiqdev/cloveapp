import CloveCore
import SwiftUI

/// Lightweight mobile-first sheet for single-select camera, lens, focal-length bucket, and keyword
/// filters. Dimensions with fewer than two distinct values in the folder auto-hide unless they
/// carry an active selection that the user can still clear.
struct MetadataFilterSheet: View {
    let browsing: BrowsingModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    private var options: PhotoMetadataFilterOptions { browsing.metadataFilterOptions }
    private var activeFilter: PhotoMetadataFilter { browsing.metadataFilter }

    private var cameras: [PhotoFilterOption<String>] {
        resolvedOptions(options.cameras, active: activeFilter.camera) { value in
            browsing.allPlacedPhotos.count { $0.metadata.camera == value }
        }
    }

    private var lenses: [PhotoFilterOption<String>] {
        resolvedOptions(options.lenses, active: activeFilter.lens) { value in
            browsing.allPlacedPhotos.count { $0.metadata.lens == value }
        }
    }

    private var focalLengths: [PhotoFilterOption<FocalLengthBucket>] {
        resolvedOptions(options.focalLengths, active: activeFilter.focalLength) { bucket in
            browsing.allPlacedPhotos.count { $0.metadata.focalLengthBucket == bucket }
        }
    }

    private var keywords: [PhotoFilterOption<String>] {
        resolvedOptions(options.keywords, active: activeFilter.keyword) { keyword in
            browsing.allPlacedPhotos.count { $0.marks.keywords.contains(keyword) }
        }
    }

    private var hasVisibleContent: Bool {
        !cameras.isEmpty || !lenses.isEmpty || !focalLengths.isEmpty || !keywords.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasVisibleContent {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            matchSummary
                            if !cameras.isEmpty {
                                listDimensionSection(
                                    title: AppLocalization.string("Camera", language: language),
                                    options: cameras,
                                    selected: activeFilter.camera,
                                    identifierPrefix: "clove.grid.metadataFilter.camera"
                                ) { value in
                                    browsing.toggleCameraFilter(value)
                                }
                            }
                            if !lenses.isEmpty {
                                listDimensionSection(
                                    title: AppLocalization.string("Lens", language: language),
                                    options: lenses,
                                    selected: activeFilter.lens,
                                    identifierPrefix: "clove.grid.metadataFilter.lens"
                                ) { value in
                                    browsing.toggleLensFilter(value)
                                }
                            }
                            if !focalLengths.isEmpty {
                                focalLengthSection
                            }
                            if !keywords.isEmpty {
                                keywordsSection
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView {
                        Label(
                            AppLocalization.string("More filters", language: language),
                            systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(
                            AppLocalization.string(
                                "No camera, lens, focal length, or keyword filters available in this folder.",
                                language: language))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("clove.grid.metadataFilter.unavailable")
                }
            }
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .navigationTitle(AppLocalization.string("More filters", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !activeFilter.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppLocalization.string("Clear", language: language)) {
                            browsing.clearMetadataFilter()
                        }
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityIdentifier("clove.grid.metadataFilter.clear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done", language: language)) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.clove.accent)
                    .accessibilityIdentifier("clove.grid.metadataFilter.done")
                }
            }
        }
        .background(Color.clove.surface.sheet)
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.grid.metadataFilter.sheet")
    }

    private var matchSummary: some View {
        Text(
            AppLocalization.format(
                "Showing %lld of %lld", language: language,
                Int64(browsing.photos.count), Int64(browsing.allPlacedPhotos.count))
        )
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.clove.text.secondary)
        .accessibilityIdentifier("clove.grid.metadataFilter.summary")
    }

    private func listDimensionSection(
        title: String,
        options: [PhotoFilterOption<String>],
        selected: String?,
        identifierPrefix: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                    let isSelected = selected == option.value
                    Button {
                        onSelect(option.value)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.clove.accent)
                                .opacity(isSelected ? 1 : 0)
                                .frame(width: 16)
                            Text(option.value)
                                .font(.subheadline)
                                .foregroundStyle(Color.clove.text.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(option.count.formatted(.number.locale(language.locale)))
                                .font(.caption)
                                .foregroundStyle(Color.clove.text.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("\(identifierPrefix).\(option.value)")
                    if index < options.count - 1 {
                        Divider()
                            .overlay(Color.clove.separator)
                            .padding(.leading, 40)
                    }
                }
            }
            .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var focalLengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(AppLocalization.string("Focal length", language: language))
            VStack(spacing: 0) {
                ForEach(Array(focalLengths.enumerated()), id: \.element.value) { index, option in
                    let isSelected = activeFilter.focalLength == option.value
                    Button {
                        browsing.toggleFocalLengthFilter(option.value)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.clove.accent)
                                .opacity(isSelected ? 1 : 0)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(
                                    AppLocalization.focalLengthBucketTitle(
                                        option.value, language: language)
                                )
                                .font(.subheadline)
                                .foregroundStyle(Color.clove.text.primary)
                                Text(option.value.rangeLabel)
                                    .font(.caption)
                                    .foregroundStyle(Color.clove.text.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(option.count.formatted(.number.locale(language.locale)))
                                .font(.caption)
                                .foregroundStyle(Color.clove.text.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier(
                        "clove.grid.metadataFilter.focalLength.\(option.value.rawValue)")
                    if index < focalLengths.count - 1 {
                        Divider()
                            .overlay(Color.clove.separator)
                            .padding(.leading, 40)
                    }
                }
            }
            .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(AppLocalization.string("Keywords", language: language))
            MetadataChipLayout(spacing: 8) {
                ForEach(keywords, id: \.value) { option in
                    let isSelected = activeFilter.keyword == option.value
                    Button {
                        browsing.toggleKeywordFilter(option.value)
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.value)
                                .lineLimit(1)
                            Text(option.count.formatted(.number.locale(language.locale)))
                                .font(.caption)
                                .foregroundStyle(
                                    isSelected
                                        ? Color.white.opacity(0.85)
                                        : theme.tokens.secondaryText.color)
                        }
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.white : theme.tokens.primaryText.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 36)
                        .background(
                            isSelected ? Color.clove.accent : Color.clove.surface.card,
                            in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("clove.grid.metadataFilter.keyword.\(option.value)")
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.clove.text.secondary)
            .textCase(.uppercase)
    }

    /// Preserves an active selection even when the dimension dropped below two distinct values
    /// after edits, so the user can always see and clear it directly.
    private func resolvedOptions<Value: Hashable>(
        _ available: [PhotoFilterOption<Value>],
        active: Value?,
        count: (Value) -> Int
    ) -> [PhotoFilterOption<Value>] {
        guard let active else { return available }
        if available.contains(where: { $0.value == active }) {
            return available
        }
        return [PhotoFilterOption(value: active, count: count(active))] + available
    }
}

/// Compact summary strip shown above the grid whenever any secondary filter is active, with
/// per-chip removal and a one-tap Clear action.
struct ActiveMetadataFilterBar: View {
    let browsing: BrowsingModel
    var onEdit: (() -> Void)?
    @Environment(\.appLanguage) private var language

    private var filter: PhotoMetadataFilter { browsing.metadataFilter }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.clove.text.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.clove.surface.card, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                AppLocalization.string("More filters", language: language)
                            )
                            .accessibilityIdentifier("clove.grid.metadataFilter.bar.edit")
                        }
                        if let camera = filter.camera {
                            activeChip(
                                title: camera,
                                symbol: "camera",
                                identifier: "clove.grid.metadataFilter.active.camera"
                            ) {
                                browsing.toggleCameraFilter(camera)
                            }
                        }
                        if let lens = filter.lens {
                            activeChip(
                                title: lens,
                                symbol: "camera.aperture",
                                identifier: "clove.grid.metadataFilter.active.lens"
                            ) {
                                browsing.toggleLensFilter(lens)
                            }
                        }
                        if let bucket = filter.focalLength {
                            activeChip(
                                title: AppLocalization.focalLengthBucketLabel(
                                    bucket, language: language),
                                symbol: "scope",
                                identifier: "clove.grid.metadataFilter.active.focalLength"
                            ) {
                                browsing.toggleFocalLengthFilter(bucket)
                            }
                        }
                        if let keyword = filter.keyword {
                            activeChip(
                                title: keyword,
                                symbol: "tag",
                                identifier: "clove.grid.metadataFilter.active.keyword"
                            ) {
                                browsing.toggleKeywordFilter(keyword)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Button {
                    browsing.clearMetadataFilter()
                } label: {
                    Text(AppLocalization.string("Clear", language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.clove.accent)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clove.grid.metadataFilter.bar.clear")
            }
            .padding(.horizontal, 16)
            Divider().overlay(Color.clove.separator)
        }
        .background(Color.clove.bg.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.grid.metadataFilter.bar")
    }

    private func activeChip(
        title: String,
        symbol: String,
        identifier: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.clove.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            AppLocalization.format("Remove %@ filter", language: language, title)
        )
        .accessibilityIdentifier(identifier)
    }
}

private struct MetadataChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = rowWidth > 0 ? rowWidth + spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        widestRow = max(widestRow, rowWidth)
        return CGSize(width: proposal.width ?? widestRow, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(
                    width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
