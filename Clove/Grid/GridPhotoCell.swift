import CloveCore
import UIKit

/// One grid cell: a photo's thumbnail with its marks, or a collapsed group's cover (PRD Grid,
/// P0-03, P0-11).
///
/// A photo's cell draws the thumbnail and its overlays: the Reject flag, the rating, the colour
/// dot and the RAW set's companion badge (PRD Grid). A similar group's cells are outlined in
/// blue, and the group's count is drawn once, on its first shown cell; tapping that count opens
/// the group view (PRD P0-11). A collapsed group's cover draws the count instead of a photo's
/// marks, because the marks belong to the cover photo, not to the group (PRD Grid, collapsed).
/// In multi-select a selected cell dims and shows a system checkmark (PRD P0-09).
///
/// Design placeholder: system symbols, colours and capsules stand in for the visual design's
/// overlay art and its selected-cell treatment.
final class GridPhotoCell: UICollectionViewCell {
    private let thumbnailView = UIImageView()
    /// Dims a selected cell so the checkmark reads as a selection, not a mark (PRD P0-09).
    private let selectionScrim = UIView()
    /// The checkmark a selected cell shows (PRD P0-09).
    private let selectionBadge = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let unavailableView = UIStackView()
    private let rejectBadge = OverlayBadge(symbol: "xmark.octagon.fill", tint: .systemRed)
    private let companionBadge = OverlayBadge()
    private let ratingBadge = OverlayBadge(symbol: "star.fill", tint: .systemYellow)
    private let colourDot = ColourDotView()
    private let countButton = UIButton(type: .system)
    private let coverBadge = OverlayBadge(
        symbol: "square.stack.3d.up.fill", tint: .white, fontSize: 14,
        background: UIColor.systemBlue.withAlphaComponent(0.9))

    private var thumbnailTask: Task<Void, Never>?
    private var currentItem: GridCellItem?
    private var currentCompanions = GridCompanions()
    private var isUnavailable = false
    /// Whether the last unreadable state came from I1's scheduling pressure, not a bad file.
    private var retriesUnavailable = false
    private var isCover = false
    /// Whether multi-select has this cell's photos selected (PRD P0-09).
    private var showsSelection = false
    /// Whether the grid is in multi-select, so the count tag lets the cell toggle instead of
    /// opening the group (PRD P0-09).
    private var isSelecting = false
    private var onOpenGroup: ((GroupID) -> Void)?

    /// The transparent view that carries the cell's accessibility label. It stops below the
    /// overlay strip, so the similar group's count tag stays hittable in front of the thumbnail
    /// (PRD Grid, P0-11).
    private let photoElement = UIView()

    /// The photo element's top constraint, moved to the cell top for a collapsed group's cover.
    private var photoElementTop: NSLayoutConstraint?

    /// The height of the top overlay strip the photo element leaves to the count tag.
    private static let overlayStripHeight: CGFloat = 26

    /// Creates an empty cell; a data source configures it before it shows.
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Draws one cell item, starting its thumbnail request only when the drawn photo changes.
    ///
    /// A marks change, a filter change or a group change reconfigures the same cell without
    /// asking for its pixels again, so browsing never re-decodes a thumbnail it already shows.
    /// `isSelected` is multi-select's answer for this cell, and `isSelecting` says whether the
    /// grid is in multi-select, so the count tag can step aside for the cell's own tap
    /// (PRD P0-09).
    func configure(
        with item: GridCellItem,
        isSelected: Bool,
        isSelecting: Bool,
        thumbnails: any GridThumbnailSource,
        onOpenGroup: @escaping (GroupID) -> Void
    ) {
        let showsDifferentPhoto =
            currentItem?.id != item.id || currentItem?.photo.id != item.photo.id
        currentItem = item
        currentCompanions = thumbnails.companions(for: item.photo.id)
        showsSelection = isSelected
        self.isSelecting = isSelecting
        self.onOpenGroup = onOpenGroup
        updateOverlays()
        updateAccessibility()
        if showsDifferentPhoto {
            isUnavailable = false
            loadThumbnail(for: item.photo.id, thumbnails: thumbnails)
        } else if thumbnailTask == nil, thumbnailView.image == nil, canAskAgain {
            // A deferred or interrupted request left the cell without pixels; ask again.
            loadThumbnail(for: item.photo.id, thumbnails: thumbnails)
        }
    }

    /// Starts a thumbnail request the cell still needs after scrolling back (PRD P0-03).
    ///
    /// It never restarts a request that is still running, so a cell prepared before it appears
    /// keeps the work it already began (G1 scheduling row).
    func resumeThumbnail(using thumbnails: any GridThumbnailSource) {
        guard thumbnailTask == nil, let photo = currentItem?.photo.id,
            thumbnailView.image == nil, canAskAgain
        else { return }
        loadThumbnail(for: photo, thumbnails: thumbnails)
    }

    /// Whether the cell may ask for pixels again: always, unless a file was reported unreadable.
    ///
    /// A failure that came from scheduling pressure is marked retryable, so scrolling back asks
    /// once more; a file that cannot produce a preview stays unreadable (PRD Scan scope).
    private var canAskAgain: Bool { !isUnavailable || retriesUnavailable }

    /// Drops the pending request when the cell scrolls away (PRD P0-03).
    ///
    /// The image stays, so scrolling back shows it without a request when it already arrived.
    func cancelThumbnailRequest() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
    }

    /// Clears a reused cell so no mark or thumbnail from the previous item shows.
    override func prepareForReuse() {
        super.prepareForReuse()
        cancelThumbnailRequest()
        currentItem = nil
        currentCompanions = GridCompanions()
        isUnavailable = false
        retriesUnavailable = false
        showsSelection = false
        isSelecting = false
        thumbnailView.image = nil
        spinner.stopAnimating()
        unavailableView.isHidden = true
        selectionScrim.isHidden = true
        selectionBadge.isHidden = true
        rejectBadge.isHidden = true
        companionBadge.isHidden = true
        ratingBadge.isHidden = true
        colourDot.isHidden = true
        countButton.isHidden = true
        coverBadge.isHidden = true
        contentView.layer.borderWidth = 0
        isCover = false
        contentView.accessibilityElements = nil
        photoElement.accessibilityIdentifier = nil
        photoElement.accessibilityLabel = nil
        onOpenGroup = nil
    }

    /// Lays out the thumbnail, the loading and unreadable states and the overlay slots.
    private func setUp() {
        contentView.clipsToBounds = true
        contentView.backgroundColor = .secondarySystemBackground

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = .secondarySystemBackground

        // Design placeholder: a dimming scrim and a system checkmark stand in for the visual
        // design's selected-cell treatment (PRD P0-09).
        selectionScrim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        selectionScrim.isHidden = true
        selectionScrim.isUserInteractionEnabled = false
        selectionBadge.image = UIImage(
            systemName: "checkmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold))
        selectionBadge.tintColor = .white
        selectionBadge.contentMode = .scaleAspectFit
        selectionBadge.layer.shadowColor = UIColor.black.cgColor
        selectionBadge.layer.shadowOpacity = 0.5
        selectionBadge.layer.shadowRadius = 2
        selectionBadge.layer.shadowOffset = .zero
        selectionBadge.isHidden = true
        photoElement.isAccessibilityElement = true
        photoElement.accessibilityTraits = .image
        photoElement.isUserInteractionEnabled = false

        spinner.startAnimating()

        unavailableView.axis = .vertical
        unavailableView.alignment = .center
        unavailableView.spacing = 4
        let unavailableIcon = UIImageView(
            image: UIImage(systemName: "exclamationmark.triangle.fill"))
        unavailableIcon.tintColor = .secondaryLabel
        let unavailableLabel = UILabel()
        unavailableLabel.text = "No preview"
        unavailableLabel.font = .preferredFont(forTextStyle: .caption2)
        unavailableLabel.textColor = .secondaryLabel
        unavailableView.addArrangedSubview(unavailableIcon)
        unavailableView.addArrangedSubview(unavailableLabel)
        unavailableView.isHidden = true
        rejectBadge.isHidden = true
        companionBadge.isHidden = true
        ratingBadge.isHidden = true
        colourDot.isHidden = true
        countButton.isHidden = true
        coverBadge.isHidden = true

        countButton.addAction(
            UIAction { [weak self] _ in
                guard let group = self?.currentItem?.group?.id else { return }
                self?.onOpenGroup?(group)
            }, for: .touchUpInside)
        setCount(0)

        for view in [
            thumbnailView, selectionScrim, photoElement, spinner, unavailableView, rejectBadge,
            companionBadge, ratingBadge, colourDot, countButton, coverBadge, selectionBadge,
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            selectionScrim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionScrim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionScrim.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionScrim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            selectionBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            selectionBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            unavailableView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            unavailableView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rejectBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            rejectBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            companionBadge.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -4),
            companionBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            countButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            countButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            ratingBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            ratingBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            colourDot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            colourDot.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            colourDot.widthAnchor.constraint(equalToConstant: 10),
            colourDot.heightAnchor.constraint(equalToConstant: 10),
            coverBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            coverBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        let photoTop = photoElement.topAnchor.constraint(
            equalTo: contentView.topAnchor, constant: Self.overlayStripHeight)
        photoElementTop = photoTop
        NSLayoutConstraint.activate([
            photoTop,
            photoElement.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            photoElement.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            photoElement.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// Applies the mark, companion, group and cover slots for the current item (PRD Grid).
    private func updateOverlays() {
        guard let item = currentItem else { return }
        isCover = item.group?.isCover == true
        photoElementTop?.constant = isCover ? 0 : Self.overlayStripHeight
        let marks = item.photo.marks
        rejectBadge.isHidden = isCover || !marks.isRejected
        companionBadge.isHidden = isCover || currentCompanions.badgeText == nil
        companionBadge.setText(currentCompanions.badgeText)
        let stars = marks.rating.starCount
        ratingBadge.isHidden = isCover || stars == nil
        ratingBadge.setText(stars.map(String.init))
        let dotColour = Self.colour(for: marks.label)
        colourDot.isHidden = isCover || dotColour == nil
        colourDot.backgroundColor = dotColour
        let count = item.group?.count ?? 0
        coverBadge.isHidden = !isCover
        coverBadge.setText(isCover ? "\(count)" : nil)
        let showsCount = !isCover && item.group?.showsCount == true
        countButton.isHidden = !showsCount
        if showsCount { setCount(count) }
        // In multi-select a tap on the count tag toggles the cover's group with the cell
        // (PRD P0-09), so the tag stops opening the group view.
        countButton.isUserInteractionEnabled = !isSelecting
        selectionScrim.isHidden = !showsSelection
        selectionBadge.isHidden = !showsSelection
        contentView.layer.borderWidth = item.group != nil && !isCover ? 2 : 0
        contentView.layer.borderColor = UIColor.systemBlue.cgColor
    }

    /// Starts one request and shows whichever state it reports (PRD Scan scope).
    ///
    /// A deferred outcome is I1's scheduling pressure or a superseded request, not a broken
    /// file, so the cell keeps its loading state and asks again with a growing delay for about
    /// eight seconds while it stays visible (G1 scheduling row). Only then does it show the
    /// unreadable state, marked retryable so the cell's next display asks once more.
    private func loadThumbnail(
        for photo: PhotoIdentity, thumbnails: any GridThumbnailSource
    ) {
        thumbnailTask?.cancel()
        // A new request starts from loading, so an interrupted retry stays retryable; the
        // previous unreadable state is only kept by a request that actually reports one.
        isUnavailable = false
        retriesUnavailable = false
        thumbnailView.image = nil
        spinner.startAnimating()
        unavailableView.isHidden = true
        thumbnailTask = Task { [weak self] in
            for delay in [0, 150, 300, 600, 1_200, 2_400, 4_000] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                    if Task.isCancelled { return }
                }
                let outcome = await thumbnails.thumbnail(for: photo, priority: .visible)
                guard !Task.isCancelled, let self, self.currentItem?.photo.id == photo else {
                    return
                }
                guard case .deferred = outcome else {
                    self.show(outcome)
                    self.thumbnailTask = nil
                    return
                }
            }
            guard !Task.isCancelled, let self, self.currentItem?.photo.id == photo else { return }
            self.retriesUnavailable = true
            self.show(.unavailable)
            self.thumbnailTask = nil
        }
    }

    /// Shows the pixels, or the unreadable state instead of a blank image presented as loaded.
    ///
    /// Called with the two terminal outcomes: a deferred request never reaches here.
    private func show(_ outcome: GridThumbnailOutcome) {
        spinner.stopAnimating()
        if case .image(let image) = outcome {
            isUnavailable = false
            thumbnailView.image = UIImage(cgImage: image)
            unavailableView.isHidden = true
        } else {
            isUnavailable = true
            thumbnailView.image = nil
            unavailableView.isHidden = false
        }
        updateAccessibility()
    }

    /// Names the cell's labelled element: the file name and marks, or the cover's group
    /// (PRD Grid, PRD Scan scope).
    private func updateAccessibility() {
        guard let item = currentItem else { return }
        if let group = item.group, group.isCover {
            photoElement.accessibilityIdentifier = "clove.grid.group.\(group.id.rawValue)"
            photoElement.accessibilityLabel = "Similar group of \(group.count) photos"
            contentView.accessibilityElements = [photoElement]
            return
        }
        photoElement.accessibilityIdentifier = "clove.grid.photo.\(item.photo.id.stem)"
        photoElement.accessibilityLabel = Self.accessibilityLabel(
            for: item.photo, companions: currentCompanions, unavailable: isUnavailable,
            selected: showsSelection)
        if let group = item.group, group.showsCount, !isSelecting {
            countButton.accessibilityIdentifier = "clove.grid.group.\(group.id.rawValue)"
            countButton.accessibilityLabel = "Open the similar group of \(group.count) photos"
            contentView.accessibilityElements = [photoElement, countButton]
        } else {
            // In multi-select the count tag does not open the group, so it is not announced as
            // a control; the cell's own tap toggles the group instead (PRD P0-09).
            countButton.accessibilityIdentifier = nil
            countButton.accessibilityLabel = nil
            contentView.accessibilityElements = [photoElement]
        }
    }

    /// The count button's title, monospaced so a two-digit count never resizes the capsule.
    private func setCount(_ count: Int) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 1, leading: 5, bottom: 1, trailing: 5)
        var title = AttributedString("\(count)")
        title.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        configuration.attributedTitle = title
        countButton.configuration = configuration
    }

    /// The colour dot's fill, or nil for a clear label (PRD Grid, Marking rules).
    ///
    /// Design placeholder: system colours stand in for the visual design's label colours.
    private static func colour(for label: ColourLabel) -> UIColor? {
        switch label.colour {
        case .red: .systemRed
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .orange: .systemOrange
        case .pink: .systemPink
        case nil: label.isClear ? nil : .systemGray
        }
    }

    /// What the cell reads: its file name, every mark it draws and its selection
    /// (PRD Grid, Scan scope, P0-09).
    private static func accessibilityLabel(
        for photo: GridPhoto, companions: GridCompanions, unavailable: Bool, selected: Bool
    ) -> String {
        var parts = [photo.fileName]
        if let stars = photo.marks.rating.starCount {
            parts.append("\(stars) stars")
        }
        if let colour = photo.marks.label.colour {
            parts.append(colour.rawValue)
        } else if !photo.marks.label.isClear {
            // An unknown external label is still a label (PRD How marks reach disk, rule 9).
            parts.append(photo.marks.label.rawValue)
        }
        if photo.marks.isRejected { parts.append("Rejected") }
        if companions.hasJPEG { parts.append("JPEG companion") }
        if companions.hasHEIF { parts.append("HIF companion") }
        if unavailable { parts.append("No preview") }
        if selected { parts.append("Selected") }
        return parts.joined(separator: ", ")
    }
}

/// A small translucent capsule behind one cell overlay (PRD Grid).
///
/// Design placeholder: the visual design replaces the capsule with its own overlay art.
private final class OverlayBadge: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()

    init(
        symbol: String? = nil, tint: UIColor = .white, fontSize: CGFloat = 9,
        background: UIColor = UIColor.black.withAlphaComponent(0.6)
    ) {
        super.init(frame: .zero)
        backgroundColor = background
        layer.cornerRadius = 3
        clipsToBounds = true
        layoutMargins = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

        iconView.contentMode = .scaleAspectFit
        if let symbol {
            iconView.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: fontSize, weight: .semibold))
            iconView.tintColor = tint
        } else {
            iconView.isHidden = true
        }
        label.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        label.textColor = .white

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Draws the text, or hides it when there is nothing to name.
    func setText(_ text: String?) {
        label.text = text
        label.isHidden = text == nil
    }
}

/// A circular colour label dot (PRD Grid, Marking rules).
private final class ColourDotView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.cgColor
    }
}
