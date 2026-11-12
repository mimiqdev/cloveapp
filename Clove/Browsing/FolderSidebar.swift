import CloveCore
import SwiftUI

/// The regular-width grid's filters. Counts and the active filter belong to the browsing model.
struct FolderSidebar: View {
    let browsing: BrowsingModel
    @Environment(SettingsStore.self) private var store
    @Environment(\.cloveTheme) private var theme

    private static let ratings = (1...5).compactMap { Rating(rawValue: $0) }

    var body: some View {
        let counts = browsing.sidebarCounts
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        browsing.back()
                    } label: {
                        Label(browsing.folderTitle, systemImage: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("clove.nav.back")
                    if let source = browsing.folderSource {
                        Text(source).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            if counts.folders.count > 1 {
                Section("Locations") {
                    filterRow("All", count: counts.all, filter: .all, identifier: "all")
                    ForEach(counts.subfolders, id: \.self) { path in
                        filterRow(
                            path, count: counts.folders[path, default: 0], filter: .subfolder(path),
                            identifier: "folder.\(path)")
                    }
                }
            } else {
                filterRow("All", count: counts.all, filter: .all, identifier: "all")
            }
            Section("Filters") {
                filterRow(
                    "Unmarked", count: counts.unmarked, filter: .unmarked, identifier: "unmarked")
                filterRow(
                    "Rejected", count: counts.rejected, filter: .rejected, identifier: "rejected")
                ForEach(Self.ratings, id: \.self) { rating in
                    if let count = counts.ratings[rating], count > 0 {
                        filterRow(
                            "★\(rating.starCount ?? 0)+", count: count,
                            filter: .ratedAtLeast(rating), identifier: "rating.\(rating.rawValue)")
                    }
                }
            }
            if !counts.labels.isEmpty {
                Section("Color labels") {
                    ForEach(LabelColour.allCases, id: \.self) { colour in
                        if let count = counts.labels[colour], count > 0 {
                            row(
                                colour.rawValue, count: count,
                                selected: browsing.labelFilter == colour,
                                identifier: "label.\(colour.rawValue.lowercased())", colour: colour
                            ) {
                                browsing.setLabelFilter(colour)
                            }
                        }
                    }
                }
            }
            if store.settings.similarGroupsEnabled {
                Section("Similar groups") {
                    HStack {
                        Text("^[\(browsing.groups.count) group](inflect: true)")
                        Spacer()
                        if browsing.isFindingSimilarShots {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel("Finding similar shots")
                        } else {
                            Button {
                                Task { await browsing.runGroupingAgain() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .disabled(browsing.readingProgress != nil)
                            .accessibilityLabel("Find similar shots again")
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
                Text(count.formatted()).font(.caption)
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
}
