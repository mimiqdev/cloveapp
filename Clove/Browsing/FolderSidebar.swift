import CloveCore
import SwiftUI

/// The regular-width grid's filters. Counts and the active filter belong to the browsing model.
struct FolderSidebar: View {
    let browsing: BrowsingModel
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    private static let ratings = (1...5).compactMap { Rating(rawValue: $0) }

    private var folderDisplayName: String {
        browsing.recents.first(where: { $0.identity == browsing.state.folder }).map {
            RecentFolderSummary.name(for: $0, language: language)
        } ?? AppLocalization.string("Photos", language: language)
    }

    private var folderDisplaySource: String? {
        browsing.recents.first(where: { $0.identity == browsing.state.folder }).map {
            RecentFolderSummary.location(for: $0, language: language)
        }
    }

    var body: some View {
        let counts = browsing.sidebarCounts
        let metadataOptions = browsing.metadataFilterOptions
        let cameras = resolvedSidebarOptions(
            metadataOptions.cameras, active: browsing.metadataFilter.camera
        ) { value in
            browsing.allPlacedPhotos.count { $0.metadata.camera == value }
        }
        let lenses = resolvedSidebarOptions(
            metadataOptions.lenses, active: browsing.metadataFilter.lens
        ) { value in
            browsing.allPlacedPhotos.count { $0.metadata.lens == value }
        }
        let focalLengths = resolvedSidebarOptions(
            metadataOptions.focalLengths, active: browsing.metadataFilter.focalLength
        ) { bucket in
            browsing.allPlacedPhotos.count { $0.metadata.focalLengthBucket == bucket }
        }
        let keywords = resolvedSidebarOptions(
            metadataOptions.keywords, active: browsing.metadataFilter.keyword
        ) { keyword in
            browsing.allPlacedPhotos.count { $0.marks.keywords.contains(keyword) }
        }
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Button {
                            browsing.back()
                        } label: {
                            Label(folderDisplayName, systemImage: "chevron.left")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.string("Back", language: language))
                        .accessibilityIdentifier("clove.nav.back")
                        FolderPreparationIndicator(
                            browsing: browsing,
                            identifierPrefix: "clove.grid.preparation",
                            inListRow: true
                        )
                        .layoutPriority(1)
                    }
                    if let source = folderDisplaySource {
                        Text(source).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            if counts.folders.count > 1 {
                Section(AppLocalization.string("Locations", language: language)) {
                    filterRow(
                        AppLocalization.string("All", language: language), count: counts.all,
                        filter: .all, identifier: "all")
                    ForEach(counts.subfolders, id: \.self) { path in
                        filterRow(
                            path, count: counts.folders[path, default: 0], filter: .subfolder(path),
                            identifier: "folder.\(path)")
                    }
                }
            } else {
                filterRow(
                    AppLocalization.string("All", language: language), count: counts.all,
                    filter: .all, identifier: "all")
            }
            Section(AppLocalization.string("Filters", language: language)) {
                filterRow(
                    AppLocalization.string("Unmarked", language: language), count: counts.unmarked,
                    filter: .unmarked, identifier: "unmarked")
                filterRow(
                    AppLocalization.string("Rejected", language: language), count: counts.rejected,
                    filter: .rejected, identifier: "rejected")
                ForEach(Self.ratings, id: \.self) { rating in
                    if let count = counts.ratings[rating], count > 0 {
                        filterRow(
                            AppLocalization.format(
                                "★%lld+", language: language, Int64(rating.starCount ?? 0)),
                            count: count,
                            filter: .ratedAtLeast(rating), identifier: "rating.\(rating.rawValue)")
                    }
                }
            }
            if !counts.labels.isEmpty {
                Section(AppLocalization.string("Color labels", language: language)) {
                    ForEach(LabelColour.allCases, id: \.self) { colour in
                        if let count = counts.labels[colour], count > 0 {
                            row(
                                AppLocalization.colourName(colour, language: language),
                                count: count,
                                selected: browsing.labelFilter == colour,
                                identifier: "label.\(colour.rawValue.lowercased())", colour: colour
                            ) {
                                browsing.setLabelFilter(colour)
                            }
                        }
                    }
                }
            }
            if !cameras.isEmpty {
                Section(AppLocalization.string("Camera", language: language)) {
                    ForEach(cameras, id: \.value) { option in
                        row(
                            option.value,
                            count: option.count,
                            selected: browsing.metadataFilter.camera == option.value,
                            identifier: "camera.\(option.value)"
                        ) {
                            browsing.toggleCameraFilter(option.value)
                        }
                    }
                }
            }
            if !lenses.isEmpty {
                Section(AppLocalization.string("Lens", language: language)) {
                    ForEach(lenses, id: \.value) { option in
                        row(
                            option.value,
                            count: option.count,
                            selected: browsing.metadataFilter.lens == option.value,
                            identifier: "lens.\(option.value)"
                        ) {
                            browsing.toggleLensFilter(option.value)
                        }
                    }
                }
            }
            if !focalLengths.isEmpty {
                Section(AppLocalization.string("Focal length", language: language)) {
                    ForEach(focalLengths, id: \.value) { option in
                        row(
                            AppLocalization.focalLengthBucketLabel(
                                option.value, language: language),
                            count: option.count,
                            selected: browsing.metadataFilter.focalLength == option.value,
                            identifier: "focalLength.\(option.value.rawValue)"
                        ) {
                            browsing.toggleFocalLengthFilter(option.value)
                        }
                    }
                }
            }
            if !keywords.isEmpty {
                Section(AppLocalization.string("Keywords", language: language)) {
                    ForEach(keywords, id: \.value) { option in
                        row(
                            option.value,
                            count: option.count,
                            selected: browsing.metadataFilter.keyword == option.value,
                            identifier: "keyword.\(option.value)"
                        ) {
                            browsing.toggleKeywordFilter(option.value)
                        }
                    }
                }
            }
            if store.settings.similarGroupsEnabled {
                Section(AppLocalization.string("Similar groups", language: language)) {
                    HStack {
                        Text(
                            AppLocalization.format(
                                "%lld group", language: language, Int64(browsing.groups.count)))
                        Spacer()
                        if browsing.isFindingSimilarShots {
                            if browsing.preparationStatus.waitingReason == nil {
                                ProgressView().controlSize(.small)
                                    .accessibilityLabel(
                                        AppLocalization.string(
                                            "Finding similar shots", language: language))
                            } else {
                                Image(systemName: "pause.circle")
                                    .foregroundStyle(Color.clove.text.secondary)
                                    .frame(width: 28, height: 28)
                                    .accessibilityLabel(
                                        AppLocalization.string("Paused", language: language))
                            }
                        } else {
                            Button {
                                Task { await browsing.runGroupingAgain() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .disabled(browsing.isScanning)
                            .accessibilityLabel(
                                AppLocalization.string(
                                    "Find similar shots again", language: language)
                            )
                            .accessibilityIdentifier("clove.sidebar.grouping.runAgain")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clove.surface.sheet)
        .accessibilityIdentifier("clove.sidebar")
    }

    private func filterRow(_ title: String, count: Int, filter: PhotoFilter, identifier: String)
        -> some View
    {
        row(
            title, count: count,
            selected: browsing.labelFilter == nil && browsing.state.filter == filter,
            identifier: identifier
        ) {
            browsing.setFilter(filter)
        }
    }

    private func row(
        _ title: String, count: Int, selected: Bool, identifier: String, colour: LabelColour? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if let colour {
                    Circle().fill(Color.clove.label.colour(for: colour)).frame(width: 8, height: 8)
                }
                Text(title)
                Spacer()
                Text(count.formatted(.number.locale(language.locale))).font(.caption)
                    .foregroundStyle(
                        selected ? Color.white.opacity(0.8) : theme.tokens.secondaryText.color)
            }
            .foregroundStyle(selected ? Color.white : theme.tokens.primaryText.color)
            .contentShape(Rectangle())
        }
        .listRowBackground(selected ? theme.tokens.accent.color : Color.clear)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("clove.sidebar.\(identifier)")
    }

    private func resolvedSidebarOptions<Value: Hashable>(
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
