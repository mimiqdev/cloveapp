import CloveCore
import CloveImaging
import SwiftUI

/// One photo's detail: the preview, edge navigation and the filmstrip, with the marking HUD
/// above them (PRD P0-04, PRD Detail and marking).
///
/// The screen keeps no browsing state of its own. The current photo, the grid's order and filter,
/// the marks and the pixels all come from ``BrowsingModel`` and the open folder's
/// ``DetailImageSource``; the preview, its zoom and the marking controls are ``DetailMarkingView``,
/// which the group view draws too, so both screens mark through one path. This screen supplies
/// what is its own: the grid's order an edge tap moves through, the filmstrip below the preview,
/// and the auto-advance that follows a written mark in that order (PRD Auto-advance).
///
/// Settings come from the app-wide ``SettingsStore`` in the environment, so a change on the
/// settings screen applies the next time this screen draws; the screen reads no storage itself
/// (PRD Gesture-related settings).
///
/// The handoff's capsule and filmstrip float over the stage. Undo retains its existing wiring.
struct DetailScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    /// The pixels to show, normally the open folder's source from the browsing model.
    private let images: any DetailImageSource

    /// The app-wide settings, read live so a change on the settings screen applies the next time
    /// this screen draws (PRD Gesture-related settings).
    @Environment(SettingsStore.self) private var store

    /// The auto-advance a mark started, waiting out its pause (PRD Auto-advance).
    @State private var autoAdvance = MarkAutoAdvance()

    /// C12's current settings: the double-tap behaviour, keep-zoom and the enabled ratings.
    private var settings: AppSettings { store.settings }

    /// Creates the screen for one browsing model.
    ///
    /// `images` exists for previews and tests; the app uses the browsing model's source for the
    /// open folder. Settings come from the app-wide ``SettingsStore`` in the environment, so this
    /// screen reads no storage of its own and one source of settings serves every screen.
    init(browsing: BrowsingModel, images: (any DetailImageSource)? = nil) {
        self.browsing = browsing
        self.images = images ?? browsing.detailImages
    }

    var body: some View {
        Group {
            if let photo = browsing.currentPhoto {
                content(for: photo)
            } else {
                ContentUnavailableView {
                    Label("No photo", systemImage: "photo")
                } description: {
                    Text("Choose a photo in the grid.")
                }
                .accessibilityIdentifier("clove.detail.noPhoto")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail")
        .onDisappear {
            // Leaving detail drops a pending advance, so coming back never jumps photos
            // (PRD Auto-advance).
            autoAdvance.cancel()
        }
    }

    /// The marking controls and the preview, then the filmstrip, in the order PRD Detail and
    /// marking fixes.
    private func content(for photo: GridPhoto) -> some View {
        DetailMarkingView(
            browsing: browsing,
            photo: photo,
            settings: settings,
            saveState: browsing.saveText(for: photo.id),
            images: images,
            zoomPolicy: .detail(settings),
            order: browsing.photos,
            actions: actions)
    }

    /// What the marking view asks this screen to do: write a mark, advance after it, and move
    /// through the grid's order and filter (PRD P0-04, P0-06; PRD Auto-advance).
    private var actions: DetailMarkingActions {
        DetailMarkingActions(
            apply: { change, photo in await browsing.apply(change, to: photo.id) },
            marked: { kind, photo in startAutoAdvance(after: kind, from: photo) },
            step: { offset in showPhoto(offset: offset) },
            markingSwipeBegan: { autoAdvance.cancel() },
            openPhoto: { openPhoto($0) })
    }

    // MARK: - Navigation

    /// Opens another photo in the grid's current order and filter, without wrapping at the ends.
    private func showPhoto(offset: Int) {
        let photos = browsing.photos
        guard let current = browsing.state.currentPhoto,
            let index = photos.firstIndex(where: { $0.id == current })
        else { return }
        let target = index + offset
        guard photos.indices.contains(target) else { return }
        openPhoto(photos[target].id)
    }

    /// Shows one photo and drops an advance that was still waiting to move (PRD Auto-advance).
    private func openPhoto(_ photo: PhotoIdentity) {
        autoAdvance.cancel()
        browsing.openPhoto(photo)
    }

    // MARK: - Auto-advance

    /// Starts the pause-then-advance one written mark asks for (PRD Auto-advance).
    ///
    /// C13 decides where to go from the grid's current order and filter, so a filtered grid only
    /// offers the photos it shows, and the plan carries the marked photo so undo can return there
    /// (PRD Undo row). Every plan is recorded, including the one that stays, so undo always reads
    /// the photo of the mark it undid. The group view resolves the same plan with the group's next
    /// undecided photo instead of the grid's next one (PRD In-group culling).
    private func startAutoAdvance(after kind: MarkKind, from photo: GridPhoto) {
        let plan = rules.autoAdvancePlan(after: kind, from: photo.id, photos: browsing.photos)
        browsing.recordAutoAdvance(plan)
        autoAdvance.schedule(plan) { target in
            switch target {
            case .stay:
                break
            case .nextPhoto(let next), .nextUnmarkedPhoto(let next), .groupUndecidedPhoto(let next):
                browsing.openPhoto(next)
            }
        }
    }

    /// C13's rules for this screen's settings.
    private var rules: MarkingInputRules { MarkingInputRules(settings: settings) }
}
