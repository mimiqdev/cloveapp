import CloveCore
import SwiftUI

/// One photo's detail: its file name, current marks and save state (PRD Detail and marking,
/// P0-04, P0-08).
///
/// Design placeholder: the full-width preview, pinch and double-tap zoom, edge navigation, the
/// filmstrip and the marking bar arrive with detail, and the save-state line arrives with save
/// state and recovery.
struct DetailScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    var body: some View {
        List {
            if let photo = browsing.currentPhoto {
                Section {
                    Text(photo.fileName)
                        .font(.title2)
                        .accessibilityIdentifier("clove.detail.fileName")
                    Text(MarkSummary.text(for: photo.marks))
                        .accessibilityIdentifier("clove.detail.marks")
                } header: {
                    Text("Photo")
                }
                Section {
                    HStack(spacing: 8) {
                        ForEach(0...5, id: \.self) { stars in
                            if let rating = Rating(rawValue: stars) {
                                Button("\(stars)") { rate(rating, on: photo) }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("clove.detail.rate.\(stars)")
                            }
                        }
                    }
                } header: {
                    Text("Marking")
                } footer: {
                    Text("0 clears the rating.")
                }
                Section {
                    // PRD P0-08: the state names the storage that confirmed the change, so a
                    // Clove-stored Reject is never shown as Saved.
                    Text(SaveStateSummary.text(for: browsing.latestChange(for: photo.id)?.state))
                        .accessibilityIdentifier("clove.detail.saveState")
                } header: {
                    Text("Save state")
                }
            } else {
                Text("No photo is selected.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clove.detail.noPhoto")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail")
    }

    /// Sends one rating change to the library, keeping this photo's label and Reject
    /// (PRD P0-05, P0-08).
    private func rate(_ rating: Rating, on photo: GridPhoto) {
        Task { await browsing.apply(.rating(rating), to: photo.id) }
    }
}
