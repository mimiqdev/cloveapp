import CloveCore
import SwiftUI

/// How the Duo's photo-only strip folds the current group back into its stack (owner decision,
/// 2026-11-13, #225). Folding changes the thumbnails alone: the photo on screen, its marks and
/// the route stay as they are, and the stack's count badge reopens the group in place.
struct FilmstripGroupFold {
    /// Whether the current group draws as its stack instead of its members.
    let isFolded: Bool

    /// Folds the current group into its stack.
    let fold: () -> Void

    /// Reopens the current group's members.
    let unfold: () -> Void
}

/// Grid-order filmstrip. The current group expands on a quiet neutral surface; other groups stay
/// stacked. Tapping a stack jumps to the group's first photo; the group expands in place.
///
/// The scroll that follows the current photo runs after the change's layout settles, never
/// inside its transaction: entering or leaving a group swaps the lazy entries' identity in the
/// same change, and a scroll resolved against that transaction lands past the new content's end,
/// leaving the strip blank until the next drag (#237). In expanded Duo photo-only the marking
/// toolbar beside the strip is the one reservation of that area (#227): its sibling narrows the
/// strip's viewport, and the strip's content fills it up to the toolbar.
struct DetailFilmstrip: View {
    let photos: [GridPhoto]
    let current: PhotoIdentity?
    let thumbnails: any GridThumbnailSource
    let open: (PhotoIdentity) -> Void
    var groups: [BrowsingGroup] = []
    var finishingAction: PillAction?
    /// The Duo's photo-only detail only: folding leaves the photo open and the strip shows the
    /// group's stack instead of its members (owner decision, #225).
    var groupFold: FilmstripGroupFold?

    private struct Entry: Identifiable {
        let id: PhotoIdentity
        let photos: [GridPhoto]
        let group: BrowsingGroup?
        let expands: Bool
        let holdsCurrent: Bool
    }

    private var entries: [Entry] {
        let byPhoto = Dictionary(
            groups.flatMap { group in group.members.map { ($0, group) } },
            uniquingKeysWith: { first, _ in first })
        var seen: Set<GroupID> = []
        return photos.compactMap { photo in
            guard let group = byPhoto[photo.id] else {
                return Entry(
                    id: photo.id, photos: [photo], group: nil, expands: false,
                    holdsCurrent: photo.id == current)
            }
            guard seen.insert(group.id).inserted else { return nil }
            let members = Set(group.members)
            let shown = photos.filter { members.contains($0.id) }
            let holdsCurrent = current.map { members.contains($0) } ?? false
            return Entry(
                id: photo.id, photos: shown, group: group,
                expands: holdsCurrent && !(groupFold?.isFolded ?? false),
                holdsCurrent: holdsCurrent)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if let finishingAction { finishingAction }
            strip
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.filmstrip")
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 8) {
                    ForEach(entries) { entry in
                        if entry.expands {
                            HStack(spacing: 3) {
                                ForEach(entry.photos) { photo in frame(photo) }
                                if let groupFold {
                                    Button(action: groupFold.fold) {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.clove.text.primary)
                                            .frame(width: 20, height: 60)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Collapse group")
                                    .accessibilityIdentifier(
                                        "clove.detail.filmstrip.group.fold")
                                }
                            }
                            .padding(3)
                            .background {
                                // The group's extent, not its selection: the neutral token at
                                // 12%, on the background shape alone (owner decision,
                                // 2026-11-13, #226).
                                ExpandedGroupSurface(cornerRadius: 9)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("clove.detail.filmstrip.expandedGroup")
                        } else if let group = entry.group, let photo = entry.photos.first {
                            Button {
                                // The folded group on screen reopens in place; any other stack
                                // opens the group at its first photo (handoff interactions.md).
                                if entry.holdsCurrent, let groupFold {
                                    groupFold.unfold()
                                } else {
                                    open(photo.id)
                                }
                            } label: {
                                GroupStack(peek: 4) {
                                    DetailPhotoFrame(
                                        photo: photo, isCurrent: false, thumbnails: thumbnails,
                                        side: 54, height: 60, showsMarks: false)
                                }
                                .frame(width: 54, height: 64)
                                .overlay(alignment: .topTrailing) {
                                    GroupCountBadge(
                                        count: group.members.count, presentation: .filmstrip
                                    ).padding(2)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(photo.id)
                            .accessibilityLabel("Similar group of \(group.members.count) photos")
                            .accessibilityIdentifier(
                                "clove.detail.filmstrip.group.\(group.id.rawValue)")
                        } else if let photo = entry.photos.first {
                            frame(photo)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
            }
            .onChange(of: current, initial: true) { _, photo in
                guard let photo else { return }
                // The scroll runs after the change's layout settles, not inside its transaction:
                // entering or leaving a group swaps the lazy entries' identity in the same change,
                // and a scroll resolved against that transaction lands past the new content's end,
                // leaving the strip blank until the next drag (#237).
                Task { @MainActor in
                    withAnimation { proxy.scrollTo(photo, anchor: .center) }
                }
            }
        }
        .frame(height: 70)
    }

    private func frame(_ photo: GridPhoto) -> some View {
        Button {
            open(photo.id)
        } label: {
            DetailPhotoFrame(
                photo: photo, isCurrent: photo.id == current, thumbnails: thumbnails,
                side: 54, height: 60
            )
        }
        .buttonStyle(.plain)
        .id(photo.id)
        .accessibilityIdentifier("clove.detail.filmstrip.\(photo.id.stem.lowercased())")
    }
}
