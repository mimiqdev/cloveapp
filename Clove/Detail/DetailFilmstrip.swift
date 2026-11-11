import CloveCore
import SwiftUI

/// Grid-order filmstrip. The current group expands on a quiet tint; other groups stay stacked.
struct DetailFilmstrip: View {
    let photos: [GridPhoto]
    let current: PhotoIdentity?
    let thumbnails: any GridThumbnailSource
    let open: (PhotoIdentity) -> Void
    var groups: [BrowsingGroup] = []
    var openGroup: ((BrowsingGroup) -> Void)?

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
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(entries) { entry in
                        if entry.expands {
                            HStack(spacing: 3) {
                                ForEach(entry.photos) { photo in frame(photo) }
                            }
                            .padding(3)
                            .background {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color.clove.group).opacity(0.25)
                            }
                        } else if let group = entry.group, let photo = entry.photos.first {
                            Button {
                                if let openGroup { openGroup(group) } else { open(photo.id) }
                            } label: {
                                DetailPhotoFrame(
                                    photo: photo, isCurrent: false, thumbnails: thumbnails,
                                    side: 54, height: 60, showsMarks: false
                                )
                                .padding(.top, 4)
                                .background {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.clove.text.secondary).opacity(0.35)
                                        .padding(.horizontal, 4)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    Text(group.members.count.formatted())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.clove.bg.canvas)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.clove.group, in: Capsule())
                                        .padding(2)
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
                withAnimation { proxy.scrollTo(photo, anchor: .center) }
            }
        }
        .frame(height: 70)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.filmstrip")
    }

    private func frame(_ photo: GridPhoto) -> some View {
        Button {
            open(photo.id)
        } label: {
            DetailPhotoFrame(
                photo: photo, isCurrent: photo.id == current, thumbnails: thumbnails,
                side: 54, height: 60)
        }
        .buttonStyle(.plain)
        .id(photo.id)
        .accessibilityIdentifier("clove.detail.filmstrip.\(photo.id.stem.lowercased())")
    }
}
