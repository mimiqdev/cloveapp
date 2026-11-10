import CloveCore
import SwiftUI

/// The grid: the open folder's photos in the state's order and filter (PRD Grid, P0-03).
///
/// Design placeholder: the three-column collection view, its cell overlays, similar-group outlines
/// and long-press multi-select arrive with the grid. This list keeps the flow browsable and shows
/// the pieces the browsing state has to keep.
struct GridScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    /// Whether a tap selects a photo instead of opening it (PRD P0-09).
    @State private var isSelecting = false

    var body: some View {
        List {
            Section {
                controls
            }
            if !browsing.groups.isEmpty {
                Section("Similar groups") {
                    ForEach(browsing.groups) { group in
                        Button {
                            browsing.openGroup(group)
                        } label: {
                            Label(
                                "\(group.members.count) photos",
                                systemImage: "square.stack.3d.up")
                        }
                        .accessibilityIdentifier("clove.grid.group.\(group.id.rawValue)")
                    }
                }
            }
            Section {
                ForEach(browsing.photos) { photo in
                    row(for: photo)
                }
            } header: {
                Text("Photos")
            } footer: {
                Text("\(browsing.photos.count) shown")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.grid")
    }

    /// The filter, the order and the selection mode, all read from the browsing state
    /// (PRD P0-03, P0-09).
    private var controls: some View {
        HStack {
            Menu {
                Button("All") { browsing.setFilter(.all) }
                Button("Unmarked") { browsing.setFilter(.unmarked) }
                Button("Rejected") { browsing.setFilter(.rejected) }
                ForEach(1...5, id: \.self) { stars in
                    if let rating = Rating(rawValue: stars) {
                        Button("\(stars) stars or more") {
                            browsing.setFilter(.ratedAtLeast(rating))
                        }
                    }
                }
            } label: {
                Label(filterName, systemImage: "line.3.horizontal.decrease")
            }
            .accessibilityIdentifier("clove.grid.filter")

            Spacer()

            Menu {
                Button("Capture time") { browsing.setOrder(.captureTime) }
                Button("File name") { browsing.setOrder(.fileName) }
            } label: {
                Label(orderName, systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("clove.grid.order")

            Spacer()

            Button(isSelecting ? "Done" : "Select") { isSelecting.toggle() }
                .accessibilityIdentifier("clove.grid.selectMode")
        }
    }

    /// One photo's row: its file name and marks, opening detail or toggling selection.
    private func row(for photo: GridPhoto) -> some View {
        Button {
            if isSelecting {
                browsing.toggleSelection(photo.id)
            } else {
                browsing.openPhoto(photo.id)
            }
        } label: {
            HStack {
                if isSelecting {
                    Image(
                        systemName: browsing.state.selection.contains(photo.id)
                            ? "checkmark.circle.fill" : "circle")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.fileName)
                    Text(MarkSummary.text(for: photo.marks))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("clove.grid.photo.\(photo.id.stem)")
    }

    /// The current filter's name, so the grid shows the filter it is applying (PRD P0-03).
    private var filterName: String {
        switch browsing.state.filter {
        case .all:
            "All"
        case .unmarked:
            "Unmarked"
        case .rejected:
            "Rejected"
        case .ratedAtLeast(let rating):
            "\(rating.rawValue)+ stars"
        }
    }

    /// The current order's name (PRD P0-03).
    private var orderName: String {
        browsing.state.order == .captureTime ? "Capture time" : "File name"
    }
}
