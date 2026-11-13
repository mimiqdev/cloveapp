import CloveCore
import UIKit

/// The surface behind one group run in the Duo's split grid (owner decision, 2026-11-13, #225).
///
/// It is the handoff's `group` tint at 25% on the run's cells alone: the header draws the top
/// corners and this view draws the rest, so the two make one rounded block. Photos are never
/// tinted, and the filmstrip's expanded group keeps its own neutral surface (#226).
enum GridGroupSurface {
    /// The block's corner radius, shared by its header and its cells' surface.
    static let cornerRadius: CGFloat = 8

    /// The header's height, which holds the member count and the fold control.
    static let headerHeight: CGFloat = 30

    /// The space the block keeps above its first row and below its last.
    static let inset: CGFloat = 8

    /// The block's fill for one theme, on the shape alone.
    static func colour(theme: CloveTheme) -> UIColor {
        UIColor(theme.tokens.group.color).withAlphaComponent(0.25)
    }
}

/// The head of a group run in the Duo's split grid: how many of the group's members the filter
/// shows, and the control that folds them back into the group's stack (owner decision, #225).
///
/// Folding changes the thumbnails only. The photo on screen, its marks and the detail route stay
/// as they are, and the stack's count badge reopens the group in place.
final class GridGroupHeader: UICollectionReusableView {
    /// The supplementary kind this header is registered under.
    static let kind = "groupRunHeader"

    private let countLabel = UILabel()
    private let foldButton = UIButton(type: .system)
    private let surface = UIView()

    /// How many of the group's members the run draws.
    var count = 0 {
        didSet { draw() }
    }

    /// The group the run expands, which the fold control names.
    var group: GroupID? {
        didSet { draw() }
    }

    /// The theme in effect, so a theme change redraws the label and the surface.
    var theme: CloveTheme? {
        didSet { draw() }
    }

    /// Folds the group this header stands for.
    var fold: (GroupID) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.layer.cornerRadius = GridGroupSurface.cornerRadius
        surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        surface.isUserInteractionEnabled = false
        countLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.numberOfLines = 1
        foldButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        foldButton.accessibilityLabel = "Collapse group"
        foldButton.accessibilityIdentifier = "clove.grid.group.fold"
        foldButton.addTarget(self, action: #selector(foldGroup), for: .touchUpInside)
        for view in [surface, countLabel, foldButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: foldButton.leadingAnchor, constant: -8),
            foldButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            foldButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            foldButton.widthAnchor.constraint(equalToConstant: 44),
            foldButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Shows one run's count and fold control.
    func configure(
        count: Int, group: GroupID, theme: CloveTheme, fold: @escaping (GroupID) -> Void
    ) {
        self.count = count
        self.group = group
        self.theme = theme
        self.fold = fold
    }

    private func draw() {
        guard let group else { return }
        countLabel.text = count == 1 ? "1 photo" : "\(count.formatted()) photos"
        countLabel.accessibilityIdentifier = "clove.grid.group.count.\(group.rawValue)"
        guard let theme else { return }
        countLabel.textColor = UIColor(theme.tokens.primaryText.color)
        foldButton.tintColor = UIColor(theme.tokens.primaryText.color)
        surface.backgroundColor = GridGroupSurface.colour(theme: theme)
    }

    @objc private func foldGroup() {
        guard let group else { return }
        fold(group)
    }
}

/// The cells' share of one group run's surface: the fill under the run, rounded at its bottom
/// corners because ``GridGroupHeader`` draws the top ones (owner decision, #225).
final class GridGroupBackground: UICollectionReusableView {
    /// The decoration kind this surface is registered under.
    static let kind = "groupRunBackground"

    /// The theme's fill, kept in step with the grid by ``GridSurfaceCollectionView``.
    var tint: UIColor? {
        didSet { backgroundColor = tint }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = GridGroupSurface.cornerRadius
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// The grid's collection view, which keeps every group run's surface on the current theme.
///
/// A decoration view joins the collection view before SwiftUI's next update, and it is created
/// again after a layout change, so the surface is set on every layout pass instead of once.
final class GridSurfaceCollectionView: UICollectionView {
    /// The run surface's fill for the theme in effect.
    var groupTint: UIColor? {
        didSet { applyGroupTint() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyGroupTint()
    }

    private func applyGroupTint() {
        for case let surface as GridGroupBackground in subviews where surface.tint != groupTint {
            surface.tint = groupTint
        }
    }
}
