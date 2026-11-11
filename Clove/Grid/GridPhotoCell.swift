import CloveCore
import SwiftUI
import UIKit

/// A reusable collection cell with token-based tile presentation and bounded thumbnail retries.
final class GridPhotoCell: UICollectionViewCell {
    private var thumbnailTask: Task<Void, Never>?
    private var currentItem: GridCellItem?
    private var thumbnail: CGImage?
    private var currentCompanions = GridCompanions()
    private var isUnavailable = false
    private var retriesUnavailable = false
    private var showsSelection = false
    private var theme = CloveTheme.light
    private var hasFailed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        with item: GridCellItem, isSelected: Bool, isSelecting: Bool,
        thumbnails: any GridThumbnailSource, theme: CloveTheme, hasFailed: Bool,
        onOpenGroup: @escaping (GroupID) -> Void
    ) {
        let changesPhoto = currentItem?.photo.id != item.photo.id
        currentItem = item
        currentCompanions = thumbnails.companions(for: item.photo.id)
        showsSelection = isSelected
        self.theme = theme
        self.hasFailed = hasFailed
        if changesPhoto {
            thumbnail = nil
            isUnavailable = false
            loadThumbnail(for: item.photo.id, thumbnails: thumbnails)
        } else if thumbnailTask == nil, thumbnail == nil, canAskAgain {
            loadThumbnail(for: item.photo.id, thumbnails: thumbnails)
        }
        draw()
    }

    func resumeThumbnail(using thumbnails: any GridThumbnailSource) {
        guard thumbnailTask == nil, thumbnail == nil, canAskAgain,
            let photo = currentItem?.photo.id
        else { return }
        loadThumbnail(for: photo, thumbnails: thumbnails)
    }

    private var canAskAgain: Bool { !isUnavailable || retriesUnavailable }

    func cancelThumbnailRequest() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelThumbnailRequest()
        currentItem = nil
        thumbnail = nil
        isUnavailable = false
        retriesUnavailable = false
        contentConfiguration = nil
    }

    private func draw() {
        guard let item = currentItem else { return }
        let tile = GridTile(
            item: item, thumbnail: thumbnail, companions: currentCompanions,
            isUnavailable: isUnavailable, isSelected: showsSelection, hasFailed: hasFailed)
        let theme = theme
        contentConfiguration = UIHostingConfiguration {
            tile.environment(\.cloveTheme, theme)
        }
        .margins(.all, 0)
    }

    /// Deferred reads retry with the existing bounded backoff; unreadable files remain stable.
    private func loadThumbnail(for photo: PhotoIdentity, thumbnails: any GridThumbnailSource) {
        thumbnailTask?.cancel()
        isUnavailable = false
        retriesUnavailable = false
        thumbnailTask = Task { [weak self] in
            for delay in [0, 150, 300, 600, 1_200, 2_400, 4_000] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled else { return }
                let outcome = await thumbnails.thumbnail(for: photo, priority: .visible)
                guard !Task.isCancelled, let self, self.currentItem?.photo.id == photo else {
                    return
                }
                switch outcome {
                case .image(let image):
                    self.thumbnail = image
                    self.isUnavailable = false
                case .unavailable:
                    self.thumbnail = nil
                    self.isUnavailable = true
                case .deferred:
                    continue
                }
                self.thumbnailTask = nil
                self.draw()
                return
            }
            guard !Task.isCancelled, let self, self.currentItem?.photo.id == photo else { return }
            self.retriesUnavailable = true
            self.isUnavailable = true
            self.thumbnailTask = nil
            self.draw()
        }
    }
}

/// The handoff's square photo, group stack, no-preview state and selection overlays.
private struct GridTile: View {
    let item: GridCellItem
    let thumbnail: CGImage?
    let companions: GridCompanions
    let isUnavailable: Bool
    let isSelected: Bool
    let hasFailed: Bool
    @Environment(\.cloveTheme) private var theme

    private var isCover: Bool { item.group?.isCover == true }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if isCover {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.clove.text.secondary).opacity(0.35)
                        .padding(.horizontal, 10).padding(.bottom, 6)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.clove.surface.card)
                        .padding(.horizontal, 5).padding(.top, 4).padding(.bottom, 3)
                }
                image
                    .frame(width: proxy.size.width, height: proxy.size.height - (isCover ? 8 : 0))
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: isCover ? 5 : 0))
                    .opacity(item.photo.marks.isRejected ? theme.tokens.rejectedOpacity : 1)
                    .overlay(alignment: .bottomLeading) { rating }
                    .overlay(alignment: .topTrailing) { label }
                    .overlay(alignment: .topLeading) { cornerMarkers }
                    .overlay(alignment: .bottomTrailing) { bottomMarkers }
            }
            .background(Color.clove.surface.card)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            isCover
                ? "clove.grid.group.\(item.group?.id.rawValue ?? "")"
                : "clove.grid.photo.\(item.photo.id.stem)")
    }

    @ViewBuilder private var image: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
        } else if isUnavailable {
            VStack(spacing: 3) {
                Text((item.photo.fileName as NSString).pathExtension.uppercased())
                    .font(.caption.weight(.semibold))
                Text("No preview").font(.caption2)
            }
            .foregroundStyle(Color.clove.text.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clove.surface.card)
        } else {
            Rectangle().fill(Color.clove.surface.card)
        }
    }

    @ViewBuilder private var rating: some View {
        if !isCover, item.photo.marks.rating.rawValue > 0 {
            HStack(spacing: 1) {
                Image(systemName: "star.fill").foregroundStyle(Color.clove.rating.on)
                Text(item.photo.marks.rating.rawValue.formatted()).foregroundStyle(
                    Color.clove.text.primary)
            }
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Color.clove.surface.glass, in: Capsule())
            .padding(4)
        }
    }

    @ViewBuilder private var label: some View {
        if !isCover, !item.photo.marks.label.isClear {
            Circle()
                .fill(Color.clove.label.colour(for: item.photo.marks.label.colour))
                .frame(width: 8, height: 8)
                .overlay { Circle().strokeBorder(Color.clove.text.primary, lineWidth: 1) }
                .padding(5)
        }
    }

    private var cornerMarkers: some View {
        HStack(spacing: 3) {
            if companions.badgeText != nil {
                Image(systemName: "square.on.square")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.clove.text.primary)
                    .padding(2)
                    .background(Color.clove.surface.glass, in: RoundedRectangle(cornerRadius: 2))
            }
            if hasFailed {
                Circle().fill(Color.clove.status.failed).frame(width: 7, height: 7)
            }
        }
        .padding(4)
    }

    private var bottomMarkers: some View {
        HStack(spacing: 3) {
            if let group = item.group, isCover || group.showsCount {
                Text(group.count.formatted())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.clove.bg.canvas)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.clove.group, in: Capsule())
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.clove.bg.canvas, Color.clove.accent)
                    .font(.system(size: 20))
            }
        }
        .padding(4)
    }

    private var accessibilityLabel: String {
        if isCover { return "Similar group of \(item.group?.count ?? 0) photos" }
        var parts = [item.photo.fileName]
        if item.photo.marks.rating.rawValue > 0 {
            parts.append("\(item.photo.marks.rating.rawValue) stars")
        }
        if let colour = item.photo.marks.label.colour {
            parts.append(colour.rawValue)
        } else if !item.photo.marks.label.isClear {
            parts.append(item.photo.marks.label.rawValue)
        }
        if item.photo.marks.isRejected { parts.append("Rejected") }
        if companions.hasJPEG { parts.append("JPEG companion") }
        if companions.hasHEIF { parts.append("HIF companion") }
        if isUnavailable { parts.append("No preview") }
        if isSelected { parts.append("Selected") }
        return parts.joined(separator: ", ")
    }
}
