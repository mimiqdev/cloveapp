import CloveCore
import SwiftUI

/// The group view: one group's photos in order, on the current member (PRD In-group culling,
/// P0-12).
///
/// Design placeholder: synchronized zoom, progressive elimination, both finishing actions and
/// advancing to the next group arrive with in-group culling.
struct GroupScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    var body: some View {
        List {
            Section {
                ForEach(browsing.groupPhotos) { photo in
                    Button {
                        browsing.showGroupPhoto(photo.id)
                    } label: {
                        HStack {
                            Image(systemName: isCurrent(photo) ? "eye" : "circle.dashed")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.fileName)
                                Text(MarkSummary.text(for: photo.marks))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("clove.group.photo.\(photo.id.stem)")
                }
            } header: {
                Text("\(browsing.groupPhotos.count) photos in this group")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.group")
    }

    /// Whether this photo is the one the group view is on (PRD P0-12, P0-14).
    private func isCurrent(_ photo: GridPhoto) -> Bool {
        browsing.state.groupPosition?.photo == photo.id
    }
}
