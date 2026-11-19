import CloveCore
import SwiftUI
import UIKit
import os

/// Describes how an unfolded group member tile sits inside its horizontal inline tray.
struct GridGroupTrayPosition: Equatable, Sendable {
    let memberIndex: Int
    let memberCount: Int
    let connectsLeading: Bool
    let connectsTrailing: Bool
}

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
    private var language = ResolvedAppLanguage.english
    private var isSelecting = false
    private(set) var trayPosition: GridGroupTrayPosition?
    private var onOpenGroup: (GroupID) -> Void = { _ in }
    private var pixelLoadSignpost: (token: UUID, state: OSSignpostIntervalState)?
    private(set) var hostingConfigurationCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        applyClipping()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyClipping()
    }

    private func applyClipping() {
        let shouldClip = (trayPosition == nil)
        clipsToBounds = shouldClip
        contentView.clipsToBounds = shouldClip
    }

    private var currentPeekingIDs: [PhotoIdentity] {
        guard let group = currentItem?.group, group.isCover else { return [] }
        return group.peekingPhotos
    }

    func configure(
        with item: GridCellItem, isSelected: Bool, isCurrent: Bool = false, isSelecting: Bool,
        trayPosition: GridGroupTrayPosition? = nil,
        thumbnails: any GridThumbnailSource, theme: CloveTheme,
        language: ResolvedAppLanguage = .english,
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
        self.language = language
        self.isSelecting = isSelecting
        self.trayPosition = trayPosition
        applyClipping()
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
        trayPosition = nil
        applyClipping()
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
            isSelecting: isSelecting, trayPosition: trayPosition, openGroup: onOpenGroup)
        let theme = theme
        let language = language
        contentConfiguration = UIHostingConfiguration {
            tile
                .environment(\.cloveTheme, theme)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
        }
        .margins(.all, 0)
        applyClipping()
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
    /// Indicates the photo or collapsed stack currently open in detail in Split Photo Preview.
    var isCurrent = false
    let isSelecting: Bool
    var trayPosition: GridGroupTrayPosition? = nil
    let openGroup: (GroupID) -> Void
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    private var isCover: Bool { item.group?.isCover == true }
    private var isExpandedGroupMember: Bool { item.group != nil && !isCover }
    private var tileCornerRadius: CGFloat {
        if isCover { return 5 }
        return isExpandedGroupMember ? 6 : 0
    }

    var body: some View {
        GeometryReader { proxy in
            if let tray = trayPosition {
                let leadingInset: CGFloat = tray.connectsLeading ? 2 : 4
                let trailingInset: CGFloat = tray.connectsTrailing ? 2 : 4
                let verticalInset: CGFloat = 4
                let photoWidth = max(0, proxy.size.width - leadingInset - trailingInset)
                let photoHeight = max(0, proxy.size.height - verticalInset * 2)
                ZStack(alignment: .topLeading) {
                    InlineGroupTraySurface(
                        connectsLeading: tray.connectsLeading,
                        connectsTrailing: tray.connectsTrailing
                    )
                    .frame(
                        width: proxy.size.width + (tray.connectsTrailing ? 1.5 : 0),
                        height: proxy.size.height)
                    photoContent(width: photoWidth, height: photoHeight)
                        .padding(.top, verticalInset)
                        .padding(.leading, leadingInset)
                    if tray.memberIndex == 0 {
                        trayGroupPill(count: tray.memberCount)
                            .padding(7)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            } else {
                Group {
                    if isCover {
                        GroupStack(peekingImages: peekingThumbnails) { image }
                            .opacity(item.isDimmed ? theme.tokens.rejectedOpacity : 1)
                            .overlay(alignment: .bottomLeading) { rating }
                            .overlay(alignment: .bottomTrailing) { label }
                            .overlay(alignment: .bottomTrailing) { bottomMarkers }
                    } else {
                        photoContent(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isCurrent {
                        CurrentPhotoIndicator(cornerRadius: tileCornerRadius)
                            .frame(
                                width: proxy.size.width,
                                height: isCover
                                    ? max(0, proxy.size.height - 8) : proxy.size.height
                            )
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let group = item.group, isCover {
                        GroupCountBadge(count: group.count, presentation: .grid).padding(4)
                    }
                }
                .background {
                    if isExpandedGroupMember {
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
                .accessibilityLabel(
                    AppLocalization.format(
                        "Open the similar group of %lld photos", language: language,
                        Int64(group.count))
                )
                .accessibilityIdentifier("clove.grid.group.\(group.id.rawValue)")
            }
        }
    }

    private func photoContent(width: CGFloat, height: CGFloat) -> some View {
        image
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
            .opacity(item.isDimmed ? theme.tokens.rejectedOpacity : 1)
            .overlay(alignment: .bottomLeading) { rating }
            .overlay(alignment: .bottomTrailing) { label }
            .overlay(alignment: .bottomTrailing) { bottomMarkers }
    }

    private func trayGroupPill(count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "square.stack")
                .font(.system(size: 9, weight: .semibold))
            Text(count.formatted(.number.locale(language.locale)))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(Color.white.opacity(0.95))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.58), in: Capsule())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var image: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
        } else if isUnavailable {
            VStack(spacing: 3) {
                Text((item.photo.fileName as NSString).pathExtension.uppercased())
                    .font(.caption.weight(.semibold))
                Text(AppLocalization.string("No preview", language: language)).font(.caption2)
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
                Text(stars.formatted(.number.locale(language.locale))).foregroundStyle(
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
            return AppLocalization.format(
                "Similar group of %lld photos", language: language,
                Int64(item.group?.count ?? 0))
        }
        var parts = [item.photo.fileName]
        if let group = item.group, !group.isCover, let memberIndex = group.memberIndex {
            parts.append(
                AppLocalization.format(
                    "Group %lld of %lld", language: language,
                    Int64(memberIndex + 1), Int64(group.count)))
        }
        if let stars = item.photo.marks.rating.starCount {
            parts.append(AppLocalization.starCount(stars, language: language))
        }
        if let colour = item.photo.marks.label.colour {
            parts.append(AppLocalization.colourName(colour, language: language))
        } else if !item.photo.marks.label.isClear {
            parts.append(item.photo.marks.label.rawValue)
        }
        if item.photo.marks.isRejected {
            parts.append(AppLocalization.string("Rejected", language: language))
        }
        if companions.hasJPEG {
            parts.append(AppLocalization.string("JPEG companion", language: language))
        }
        if companions.hasHEIF {
            parts.append(AppLocalization.string("HIF companion", language: language))
        }
        if isUnavailable {
            parts.append(AppLocalization.string("No preview", language: language))
        }
        if isSelected {
            parts.append(AppLocalization.string("Selected", language: language))
        }
        return parts.joined(separator: ", ")
    }
}

/// Neutral tray band behind unfolded inline group members in select mode, connecting
/// horizontally across same-row group neighbors with rounded outer caps and no internal dividers.
private struct InlineGroupTraySurface: View {
    let connectsLeading: Bool
    let connectsTrailing: Bool

    private var trayShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: connectsLeading ? 0 : 8,
            bottomLeadingRadius: connectsLeading ? 0 : 8,
            bottomTrailingRadius: connectsTrailing ? 0 : 8,
            topTrailingRadius: connectsTrailing ? 0 : 8,
            style: .continuous)
    }

    var body: some View {
        trayShape
            .fill(Color.clove.text.primary.opacity(0.12))
            .overlay {
                InlineGroupTrayBorder(
                    connectsLeading: connectsLeading,
                    connectsTrailing: connectsTrailing,
                    cornerRadius: 8
                )
                .stroke(Color.clove.text.primary.opacity(0.20), lineWidth: 1)
            }
    }
}

private struct InlineGroupTrayBorder: Shape {
    let connectsLeading: Bool
    let connectsTrailing: Bool
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        if !connectsLeading && !connectsTrailing {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .path(in: rect.insetBy(dx: 0.5, dy: 0.5))
        }
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let halfStroke: CGFloat = 0.5
        let topY = rect.minY + halfStroke
        let bottomY = rect.maxY - halfStroke
        let leftX = connectsLeading ? rect.minX : rect.minX + halfStroke
        let rightX = connectsTrailing ? rect.maxX : rect.maxX - halfStroke

        var path = Path()
        if !connectsLeading && connectsTrailing {
            path.move(to: CGPoint(x: rightX, y: topY))
            path.addArc(
                tangent1End: CGPoint(x: leftX, y: topY),
                tangent2End: CGPoint(x: leftX, y: bottomY),
                radius: radius)
            path.addArc(
                tangent1End: CGPoint(x: leftX, y: bottomY),
                tangent2End: CGPoint(x: rightX, y: bottomY),
                radius: radius)
            path.addLine(to: CGPoint(x: rightX, y: bottomY))
        } else if connectsLeading && !connectsTrailing {
            path.move(to: CGPoint(x: leftX, y: topY))
            path.addArc(
                tangent1End: CGPoint(x: rightX, y: topY),
                tangent2End: CGPoint(x: rightX, y: bottomY),
                radius: radius)
            path.addArc(
                tangent1End: CGPoint(x: rightX, y: bottomY),
                tangent2End: CGPoint(x: leftX, y: bottomY),
                radius: radius)
            path.addLine(to: CGPoint(x: leftX, y: bottomY))
        } else {
            path.move(to: CGPoint(x: leftX, y: topY))
            path.addLine(to: CGPoint(x: rightX, y: topY))
            path.move(to: CGPoint(x: leftX, y: bottomY))
            path.addLine(to: CGPoint(x: rightX, y: bottomY))
        }
        return path
    }
}
