import CloveCore
import Foundation
import Observation

/// The browsing state every screen reads and changes (PRD P0-13, P0-14).
///
/// The state belongs to this model, never to a view's `@State`, so the compact stack and the
/// split layout show the same folder, photo, filter, selection and group place when a fold, an
/// unfold or a resize changes the layout (PRD P0-14, G1 fold-state row). The model also keeps the
/// state in the shape CloveCore can validate and store, so a launch restores what it can and falls
/// back to entry for the rest.
@MainActor
@Observable
final class BrowsingModel {
    /// The seam the screens read through; U2 and U3 replace it with folder access, the scan, the
    /// order, writes and grouping.
    private let library: any FolderLibrary

    /// The scene's browsing state (PRD P0-14).
    private(set) var state: BrowsingState

    /// Why entry must ask for the saved folder again, or nil (PRD P0-02). Entry shows the message
    /// until U2 writes its copy.
    private(set) var folderFailure: FolderAccessFailure?

    /// The groups the open folder publishes, in grid order (PRD P0-11).
    private(set) var groups: [BrowsingGroup]

    /// The library's photos with their marks, before this state's order and filter (PRD P0-03).
    private var storedPhotos: [GridPhoto]

    /// Whether this scene has already read its saved state, so a later appearance never
    /// overwrites what the user has done since.
    private var hasRestored = false

    /// Creates the model over one library, starting at entry unless a state is passed in.
    init(library: any FolderLibrary, state: BrowsingState = .entry) {
        self.library = library
        self.state = state
        self.groups = library.groups
        self.storedPhotos = library.photos
    }

    /// The photos the grid shows: this state's order and filter, applied to the folder's photos
    /// (PRD P0-03). Filtering never reorders, and neither choice changes a stored photo.
    var photos: [GridPhoto] {
        PhotoOrdering(photos: storedPhotos).photos(order: state.order, matching: state.filter)
    }

    /// Whether the open folder holds photos to browse (PRD P0-01).
    var hasFolderContents: Bool { !storedPhotos.isEmpty }

    /// The photo the detail route shows, with its current marks (PRD Detail and marking).
    var currentPhoto: GridPhoto? {
        guard let id = state.currentPhoto else { return nil }
        return storedPhotos.first { $0.id == id }
    }

    /// The open group's photos with their marks, in the group's member order (PRD P0-12).
    var groupPhotos: [GridPhoto] {
        guard let position = state.groupPosition,
            let group = groups.first(where: { $0.id == position.group })
        else { return [] }
        var byIdentity: [PhotoIdentity: GridPhoto] = [:]
        for photo in storedPhotos { byIdentity[photo.id] = photo }
        return group.members.compactMap { byIdentity[$0] }
    }

    /// Opens the library's folder and shows its grid (PRD Entry, P0-01).
    ///
    /// A folder that opens answers whatever the last failed open left on entry, so the message
    /// goes with it (PRD P0-02).
    func openFolder() {
        folderFailure = nil
        state.folder = library.folder
        state.currentPhoto = nil
        state.selection = []
        state.groupPosition = nil
        state.route = .grid
    }

    /// Shows one photo's detail (PRD Detail and marking).
    func openPhoto(_ photo: PhotoIdentity) {
        state.currentPhoto = photo
        state.route = .detail
    }

    /// Opens a group's view on its first member (PRD In-group culling).
    func openGroup(_ group: BrowsingGroup) {
        guard let first = group.members.first else { return }
        state.groupPosition = BrowsingGroupPosition(group: group.id, photo: first)
        state.route = .group
    }

    /// Moves the open group view to another member (PRD P0-12).
    func showGroupPhoto(_ photo: PhotoIdentity) {
        guard let position = state.groupPosition else { return }
        state.groupPosition = BrowsingGroupPosition(group: position.group, photo: photo)
    }

    /// Shows Clove's settings (PRD Gesture-related settings).
    func showSettings() {
        state.route = .settings
    }

    /// Returns to the screen the current one came from (PRD P0-13).
    ///
    /// The grid's parent is entry, and detail and the group view return to the grid. Settings
    /// keeps the folder it was opened over, so closing them returns to the grid when a folder is
    /// open and to entry when none is.
    func back() {
        switch state.route {
        case .entry:
            break
        case .grid:
            state.route = .entry
        case .detail, .group, .settings:
            state.route = state.folder == nil ? .entry : .grid
        }
    }

    /// Changes the grid filter without touching the order or the current photo (PRD P0-03).
    func setFilter(_ filter: PhotoFilter) {
        state.filter = filter
    }

    /// Changes the grid order without touching the filter or the current photo (PRD P0-03).
    func setOrder(_ order: PhotoOrder) {
        state.order = order
    }

    /// Adds one photo to the multi-selection or removes it (PRD P0-09).
    func toggleSelection(_ photo: PhotoIdentity) {
        if state.selection.contains(photo) {
            state.selection.remove(photo)
        } else {
            state.selection.insert(photo)
        }
    }

    /// Applies marks to one photo through the library and shows them at once (PRD P0-05).
    func apply(_ marks: PhotoMarks, to photo: PhotoIdentity) {
        library.apply(marks, to: photo)
        storedPhotos = library.photos
    }

    /// Restores this scene's saved state through CloveCore's validation (PRD P0-14).
    ///
    /// The folder's availability comes from the caller because folder access owns it: this build
    /// always passes the library's contents, and U2 passes what C11 reported, so an unavailable
    /// folder starts at entry with the reason entry explains (PRD P0-02). Restoring runs once per
    /// scene; later appearances keep whatever the user has done.
    func restore(from data: Data?, folderAvailability: FolderAvailability? = nil) {
        guard !hasRestored else { return }
        hasRestored = true
        let folder = folderAvailability ?? .available(library.contents)
        let restored = BrowsingState.decoded(from: data).restored(from: folder)
        state = restored.state
        folderFailure = restored.folderFailure
        groups = library.groups
        storedPhotos = library.photos
    }
}
