import CloveCore
import SwiftUI
import UIKit
import os

/// A reusable collection cell with token-based tile presentation and bounded thumbnail retries.
final class GridPhotoCell: UICollectionViewCell {
    private var thumbnailTask: Task<Void, Never>?
    private var peekingTasks: [PhotoIdentity: Task<Void, Never>] = [:]
    private var currentItem: GridCellItem?
    private var thumbnail: CGImage?
    private var peekingThumbnails: [PhotoIdentity: CGImage] = [:]
    private var currentCompanions = GridCompanions()
    private var isUnavailable = false
    private var retriesUnavailable = false
    private var peekingUnavailable: Set<PhotoIdentity> = []
    private var peekingRetriesUnavailable: Set<PhotoIdentity> = []
    private var showsSelection = false
    private var showsCurrent = false
    private var theme = CloveTheme.light
    private var isSelecting = false
    private var onOpenGroup: (GroupID) -> Void = { _ in }
    private var pixelLoadSignpost: (token: UUID, state: OSSignpostIntervalState)?
    private(set) var hostingConfigurationCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var currentPeekingIDs: [PhotoIdentity] {
        guard let group = currentItem?.group, group.isCover else { return [] }
        return group.peekingPhotos
    }

    func configure(
        with item: GridCellItem, isSelected: Bool, isCurrent: Bool = false, isSelecting: Bool,
        thumbnails: any GridThumbnailSource, theme: CloveTheme,
        onOpenGroup: @escaping (GroupID) -> Void
    ) {
        let configureInterval = PerformanceSignpost.gridCell.beginInterval(
            "GridCellConfigure", id: PerformanceSignpost.gridCell.makeSignpostID())
        defer { PerformanceSignpost.gridCell.endInterval("GridCellConfigure", configureInterval) }

        let changesPhoto = currentItem?.photo.id != item.photo.id
        currentItem = item
        currentCompanions = thumbnails.companions(for: item.photo.id)
        showsSelection = isSelected
        showsCurrent = isCurrent
        self.theme = theme
        self.isSelecting = isSelecting
        self.onOpenGroup = onOpenGroup
        if changesPhoto {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            endPixelLoadSignpost()
            thumbnail = nil
            isUnavailable = false
            retriesUnavailable = false
            resolveOrLoadThumbnail(for: item.photo.id, thumbnails: thumbnails)
        } else if thumbnailTask == nil, thumbnail == nil, canAskAgain {
            resolveOrLoadThumbnail(for: item.photo.id, thumbnails: thumbnails)
        }
        reconcilePeekingThumbnails(using: thumbnails)
        draw()
    }

    func resumeThumbnail(using thumbnails: any GridThumbnailSource) {
        var resolvedSynchronously = false
        if thumbnailTask == nil, thumbnail == nil, canAskAgain,
            let photo = currentItem?.photo.id
        {
            resolvedSynchronously = resolveOrLoadThumbnail(for: photo, thumbnails: thumbnails)
        }
        for photo in currentPeekingIDs
        where peekingTasks[photo] == nil && peekingThumbnails[photo] == nil
            && canAskPeekingAgain(photo)
        {
            if resolveOrLoadPeekingThumbnail(for: photo, thumbnails: thumbnails) {
                resolvedSynchronously = true
            }
        }
        if resolvedSynchronously {
            draw()
        }
    }

    private var canAskAgain: Bool { !isUnavailable || retriesUnavailable }

    private func canAskPeekingAgain(_ photo: PhotoIdentity) -> Bool {
        !peekingUnavailable.contains(photo) || peekingRetriesUnavailable.contains(photo)
    }

    func cancelThumbnailRequest() {
        endPixelLoadSignpost()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        for task in peekingTasks.values { task.cancel() }
        peekingTasks.removeAll()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelThumbnailRequest()
        currentItem = nil
        thumbnail = nil
        peekingThumbnails.removeAll()
        isUnavailable = false
        retriesUnavailable = false
        peekingUnavailable.removeAll()
        peekingRetriesUnavailable.removeAll()
        contentConfiguration = nil
    }

    private func beginPixelLoadSignpost() -> UUID {
        endPixelLoadSignpost()
        let token = UUID()
        let state = PerformanceSignpost.gridCell.beginInterval(
            "GridCellPixelLoad", id: PerformanceSignpost.gridCell.makeSignpostID())
        pixelLoadSignpost = (token, state)
        return token
    }

    private func endPixelLoadSignpost(for token: UUID? = nil) {
        guard let active = pixelLoadSignpost else { return }
        if let token, active.token != token { return }
        pixelLoadSignpost = nil
        PerformanceSignpost.gridCell.endInterval("GridCellPixelLoad", active.state)
    }

    private func draw() {
        guard let item = currentItem else { return }
        hostingConfigurationCount += 1
        let peeking = currentPeekingIDs.map { peekingThumbnails[$0] }
        let tile = GridTile(
            item: item, thumbnail: thumbnail, peekingThumbnails: peeking,
            companions: currentCompanions,
            isUnavailable: isUnavailable, isSelected: showsSelection, isCurrent: showsCurrent,
            isSelecting: isSelecting, openGroup: onOpenGroup)
        let theme = theme
        contentConfiguration = UIHostingConfiguration {
            tile.environment(\.cloveTheme, theme)
        }
        .margins(.all, 0)
    }

    @discardableResult
    private func resolveOrLoadThumbnail(
        for photo: PhotoIdentity, thumbnails: any GridThumbnailSource
    ) -> Bool {
        if let cached = thumbnails.cachedThumbnail(for: photo) {
            switch cached {
            case .image(let image):
                thumbnail = image
                isUnavailable = false
                retriesUnavailable = false
                return true
            case .unavailable:
                thumbnail = nil
                isUnavailable = true
                retriesUnavailable = false
                return true
            case .deferred:
                break
            }
        }
        loadThumbnail(for: photo, thumbnails: thumbnails)
        return false
    }

    @discardableResult
    private func resolveOrLoadPeekingThumbnail(
        for photo: PhotoIdentity, thumbnails: any GridThumbnailSource
    ) -> Bool {
        if let cached = thumbnails.cachedThumbnail(for: photo) {
            switch cached {
            case .image(let image):
                peekingThumbnails[photo] = image
                peekingUnavailable.remove(photo)
                peekingRetriesUnavailable.remove(photo)
                return true
            case .unavailable:
                peekingThumbnails.removeValue(forKey: photo)
                peekingUnavailable.insert(photo)
                peekingRetriesUnavailable.remove(photo)
                return false
            case .deferred:
                break
            }
        }
        loadPeekingThumbnail(for: photo, thumbnails: thumbnails)
        return false
    }

    private func reconcilePeekingThumbnails(using thumbnails: any GridThumbnailSource) {
        let needed = Set(currentPeekingIDs)
        for (id, task) in peekingTasks where !needed.contains(id) {
            task.cancel()
            peekingTasks.removeValue(forKey: id)
        }
        peekingThumbnails = peekingThumbnails.filter { needed.contains($0.key) }
        peekingUnavailable = peekingUnavailable.intersection(needed)
        peekingRetriesUnavailable = peekingRetriesUnavailable.intersection(needed)
        for id in currentPeekingIDs
        where peekingThumbnails[id] == nil && peekingTasks[id] == nil && canAskPeekingAgain(id) {
            resolveOrLoadPeekingThumbnail(for: id, thumbnails: thumbnails)
        }
    }

    /// Deferred reads retry with the existing bounded backoff; unreadable files remain stable.
    private func loadThumbnail(for photo: PhotoIdentity, thumbnails: any GridThumbnailSource) {
        thumbnailTask?.cancel()
        isUnavailable = false
        retriesUnavailable = false
        let signpostToken = beginPixelLoadSignpost()
        thumbnailTask = Task { [weak self] in
            defer { self?.endPixelLoadSignpost(for: signpostToken) }
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
                self.endPixelLoadSignpost(for: signpostToken)
                return
            }
            guard !Task.isCancelled, let self, self.currentItem?.photo.id == photo else { return }
            self.retriesUnavailable = true
            self.isUnavailable = true
            self.thumbnailTask = nil
            self.draw()
            self.endPixelLoadSignpost(for: signpostToken)
        }
    }

    private func loadPeekingThumbnail(
        for photo: PhotoIdentity, thumbnails: any GridThumbnailSource
    ) {
        peekingTasks[photo]?.cancel()
        peekingUnavailable.remove(photo)
        peekingRetriesUnavailable.remove(photo)
        peekingTasks[photo] = Task { [weak self] in
            for delay in [0, 150, 300, 600, 1_200, 2_400, 4_000] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled else { return }
                let outcome = await thumbnails.thumbnail(for: photo, priority: .visible)
                guard !Task.isCancelled, let self, self.currentPeekingIDs.contains(photo) else {
                    return
                }
                switch outcome {
                case .image(let image):
                    self.peekingThumbnails[photo] = image
                    self.peekingUnavailable.remove(photo)
                    self.peekingTasks.removeValue(forKey: photo)
                    self.draw()
                    return
                case .unavailable:
                    self.peekingThumbnails.removeValue(forKey: photo)
                    self.peekingUnavailable.insert(photo)
                    self.peekingTasks.removeValue(forKey: photo)
                    return
                case .deferred:
                    continue
                }
            }
            guard !Task.isCancelled, let self, self.currentPeekingIDs.contains(photo) else {
                return
            }
            self.peekingRetriesUnavailable.insert(photo)
            self.peekingUnavailable.insert(photo)
            self.peekingTasks.removeValue(forKey: photo)
        }
    }
}

/// The handoff's square photo, group stack, no-preview state and selection overlays.
private struct GridTile: View {
    let item: GridCellItem
    let thumbnail: CGImage?
    let peekingThumbnails: [CGImage?]
    let companions: GridCompanions
    let isUnavailable: Bool
    let isSelected: Bool
    /// The expanded Duo's split grid rings the member on screen (owner decision, #225).
    var isCurrent = false
    let isSelecting: Bool
    let openGroup: (GroupID) -> Void
    @Environment(\.cloveTheme) private var theme

    private var isCover: Bool { item.group?.isCover == true }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if isCover {
                    GroupStack(peekingImages: peekingThumbnails) { image }
                } else {
                    image.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
            }
            .opacity(item.isDimmed ? theme.tokens.rejectedOpacity : 1)
            .overlay(alignment: .bottomLeading) { rating }
            .overlay(alignment: .bottomTrailing) { label }
            .overlay(alignment: .bottomTrailing) { bottomMarkers }
            .overlay(alignment: .topTrailing) {
                if let group = item.group, isCover {
                    GroupCountBadge(count: group.count, presentation: .grid).padding(4)
                }
            }
            .background {
                if item.group != nil && !isCover {
                    // An expanded group's members sit on the same neutral surface as the
                    // filmstrip's group extent: `text/primary` at 12% on the background shape
                    // alone, never on the photo (owner decision, 2026-11-13, #226 filmstrip,
                    // #227 grid).
                    ExpandedGroupSurface(cornerRadius: 6)
                } else if !isCover {
                    Rectangle().fill(Color.clove.surface.card)
                }
            }
        }
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.clove.text.primary, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected || isCurrent ? .isSelected : [])
        .accessibilityIdentifier(
            isCover
                ? "clove.grid.group.\(item.group?.id.rawValue ?? "")"
                : "clove.grid.photo.\(item.photo.id.stem)"
        )
        .overlay(alignment: .topTrailing) {
            if let group = item.group, !isCover, group.showsCount {
                Button {
                    openGroup(group.id)
                } label: {
                    GroupCountBadge(count: group.count, presentation: .grid).padding(4)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isSelecting)
                .accessibilityHidden(isSelecting)
                .accessibilityLabel("Open the similar group of \(group.count) photos")
                .accessibilityIdentifier("clove.grid.group.\(group.id.rawValue)")
            }
        }
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
            .background(Color.clove.surface.sheet)
        } else {
            Rectangle().fill(Color.clove.surface.sheet)
        }
    }

    @ViewBuilder private var rating: some View {
        if !isCover, let stars = item.photo.marks.rating.starCount {
            HStack(spacing: 1) {
                Image(systemName: "star.fill").foregroundStyle(Color.clove.rating.on)
                Text(stars.formatted()).foregroundStyle(
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

    private var bottomMarkers: some View {
        HStack(spacing: 3) {
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
        if isCover {
            return "Similar group of \(item.group?.count ?? 0) photos"
        }
        var parts = [item.photo.fileName]
        if let stars = item.photo.marks.rating.starCount {
            parts.append("\(stars) stars")
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
