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

    private enum DimensionSection {
        case camera
        case lens
        case focalLength
        case keywords
    }

    var body: some View {
        let options = browsing.metadataFilterOptions
        let activeFilter = browsing.metadataFilter
        let cameras = resolvedOptions(options.cameras, active: activeFilter.camera) { value in
            browsing.allPlacedPhotos.count { $0.metadata.camera == value }
        }
        let lenses = resolvedOptions(options.lenses, active: activeFilter.lens) { value in
            browsing.allPlacedPhotos.count { $0.metadata.lens == value }
        }
        let focalLengths = resolvedOptions(
            options.focalLengths, active: activeFilter.focalLength
        ) { bucket in
            browsing.allPlacedPhotos.count { $0.metadata.focalLengthBucket == bucket }
        }
        let keywords = resolvedOptions(options.keywords, active: activeFilter.keyword) { keyword in
            browsing.allPlacedPhotos.count { $0.marks.keywords.contains(keyword) }
        }
        let firstSection: DimensionSection? =
            if !cameras.isEmpty {
                .camera
            } else if !lenses.isEmpty {
                .lens
            } else if !focalLengths.isEmpty {
                .focalLength
            } else if !keywords.isEmpty {
                .keywords
            } else {
                nil
            }

        NavigationStack {
            Group {
                if let firstSection {
                    List {
                        if !cameras.isEmpty {
                            dimensionSection(
                                title: AppLocalization.string("Camera", language: language),
                                options: cameras,
                                includesSummary: firstSection == .camera
                            ) { option in
                                filterOptionRow(
                                    title: option.value,
                                    count: option.count,
                                    isSelected: activeFilter.camera == option.value,
                                    identifier: "clove.grid.metadataFilter.camera.\(option.value)"
                                ) {
                                    browsing.toggleCameraFilter(option.value)
                                }
                            }
                        }
                        if !lenses.isEmpty {
                            dimensionSection(
                                title: AppLocalization.string("Lens", language: language),
                                options: lenses,
                                includesSummary: firstSection == .lens
                            ) { option in
                                filterOptionRow(
                                    title: option.value,
                                    count: option.count,
                                    isSelected: activeFilter.lens == option.value,
                                    identifier: "clove.grid.metadataFilter.lens.\(option.value)"
                                ) {
                                    browsing.toggleLensFilter(option.value)
                                }
                            }
                        }
                        if !focalLengths.isEmpty {
                            dimensionSection(
                                title: AppLocalization.string("Focal length", language: language),
                                options: focalLengths,
                                includesSummary: firstSection == .focalLength
                            ) { option in
                                filterOptionRow(
                                    title: AppLocalization.focalLengthBucketTitle(
                                        option.value, language: language),
                                    subtitle: option.value.rangeLabel,
                                    count: option.count,
                                    isSelected: activeFilter.focalLength == option.value,
                                    identifier:
                                        "clove.grid.metadataFilter.focalLength.\(option.value.rawValue)"
                                ) {
                                    browsing.toggleFocalLengthFilter(option.value)
                                }
                            }
                        }
                        if !keywords.isEmpty {
                            keywordsSection(
                                keywords,
                                selected: activeFilter.keyword,
                                includesSummary: firstSection == .keywords)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(12)
                    .scrollContentBackground(.hidden)
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
        .textCase(nil)
        .accessibilityIdentifier("clove.grid.metadataFilter.summary")
    }

    private func dimensionSection<Value: Hashable, Row: View>(
        title: String,
        options: [PhotoFilterOption<Value>],
        includesSummary: Bool,
        @ViewBuilder row: @escaping (PhotoFilterOption<Value>) -> Row
    ) -> some View {
        Section {
            ForEach(options, id: \.value) { option in
                row(option)
            }
        } header: {
            sectionHeader(title, includesSummary: includesSummary)
        }
        .listRowBackground(theme.tokens.card.color)
    }

    private func filterOptionRow(
        title: String,
        subtitle: String? = nil,
        count: Int,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Color.clove.text.primary)
                        .lineLimit(subtitle == nil ? 2 : 1)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.clove.text.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(count.formatted(.number.locale(language.locale)))
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, subtitle == nil ? 0 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func keywordsSection(
        _ keywords: [PhotoFilterOption<String>],
        selected: String?,
        includesSummary: Bool
    ) -> some View {
        Section {
            MetadataChipLayout(spacing: 8) {
                ForEach(keywords, id: \.value) { option in
                    let isSelected = selected == option.value
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
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("clove.grid.metadataFilter.keyword.\(option.value)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader(
                AppLocalization.string("Keywords", language: language),
                includesSummary: includesSummary)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, includesSummary: Bool) -> some View {
        if includesSummary {
            VStack(alignment: .leading, spacing: 12) {
                matchSummary
                sectionTitle(title)
            }
            .accessibilityElement(children: .contain)
        } else {
            sectionTitle(title)
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
            let size = subview.sizeThatFits(
                ProposedViewSize(width: proposal.width, height: nil))
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
            let size = subview.sizeThatFits(
                ProposedViewSize(width: bounds.width, height: nil))
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
