import CloveCore
import SwiftUI

/// Grid-order filmstrip. The current group expands on a quiet neutral surface; other groups stay
/// stacked. Tapping a stack jumps to the group's first photo; the group expands in place.
///
/// In expanded Duo photo-only, `markingWidth` reserves the bottom-right marking area beside the
/// strip (#227): the strip's viewport narrows by that much, so thumbnails never scroll under the
/// marking toolbar beside it.
struct DetailFilmstrip: View {
    let photos: [GridPhoto]
    let current: PhotoIdentity?
    let thumbnails: any GridThumbnailSource
    let open: (PhotoIdentity) -> Void
    var groups: [BrowsingGroup] = []
    var finishingAction: PillAction?
    /// The width the layout reserves beside the strip's trailing edge for the marking area, or
    /// nil for the full width.
    var markingWidth: CGFloat? = nil

    private struct Entry: Identifiable {
        let id: PhotoIdentity
        let photos: [GridPhoto]
        let group: BrowsingGroup?
        let expands: Bool
    }

    private var entries: [Entry] {
        let byPhoto = Dictionary(
            groups.flatMap { group in group.members.map { ($0, group) } },
            uniquingKeysWith: { first, _ in first })
        var seen: Set<GroupID> = []
        return photos.compactMap { photo in
            guard let group = byPhoto[photo.id] else {
                return Entry(id: photo.id, photos: [photo], group: nil, expands: false)
            }
            guard seen.insert(group.id).inserted else { return nil }
            let members = Set(group.members)
            let shown = photos.filter { members.contains($0.id) }
            return Entry(
                id: photo.id, photos: shown, group: group,
                expands: current.map { members.contains($0) } ?? false)
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
                            }
                            .padding(3)
                            .background {
                                // The group's extent, not its selection: the neutral token at 12%,
                                // on the background shape alone (owner decision, 2026-11-13, #226).
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color.clove.text.primary).opacity(0.12)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("clove.detail.filmstrip.expandedGroup")
                        } else if let group = entry.group, let photo = entry.photos.first {
                            Button {
                                open(photo.id)
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
            .padding(.trailing, markingWidth ?? 0)
            .onChange(of: current, initial: true) { _, photo in
                guard let photo else { return }
                withAnimation { proxy.scrollTo(photo, anchor: .center) }
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
