import CloveCore
import SwiftUI

/// One photo's detail: its file name and current marks (PRD Detail and marking, P0-04).
///
/// Design placeholder: the full-width preview, pinch and double-tap zoom, edge navigation, the
/// filmstrip and the marking bar arrive with detail.
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
                Section("Marking") {
                    Menu("Rate") {
                        ForEach(0...5, id: \.self) { stars in
                            if let rating = Rating(rawValue: stars) {
                                Button(stars == 0 ? "Clear rating" : "\(stars) stars") {
                                    rate(rating, on: photo)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("clove.detail.rate")
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

    /// Applies one rating and keeps this photo's label and Reject (PRD P0-05).
    private func rate(_ rating: Rating, on photo: GridPhoto) {
        var marks = photo.marks
        marks.rating = rating
        browsing.apply(marks, to: photo.id)
    }
}
