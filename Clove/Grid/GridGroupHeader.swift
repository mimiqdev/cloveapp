import CloveCore
import UIKit

/// The measurements of one group run in Photo Preview's split grid (#304, #309).
///
/// The run draws its members' extent with the shared ``ExpandedGroupSurface``, the same neutral
/// `text/primary` 12% surface the grid and the filmstrip use (#226, #227), so it adds no tint of
/// its own. The header row holds the member count and the fold control.
enum GridGroupRun {
    /// The header's height, which holds the member count and the fold control.
    static let headerHeight: CGFloat = 30

    /// The space the run keeps above its first row and below its last.
    static let inset: CGFloat = 8
}

/// The head of a group run in Photo Preview's split grid: how many of the group's members the
/// filter shows, and the control that folds them back into the group's stack (#304, #309).
///
/// Folding returns the pane to the folder Timeline on the group's Representative Photo. The
/// photo on screen keeps its marks and the detail route, and the stack's cover reopens the group.
final class GridGroupHeader: UICollectionReusableView {
    /// The supplementary kind this header is registered under.
    static let kind = "groupRunHeader"

    private let countLabel = UILabel()
    private let foldButton = UIButton(type: .system)

    /// How many of the group's members the run draws.
    var count = 0 {
        didSet { draw() }
    }

    /// The group the run expands, which the fold control names.
    var group: GroupID? {
        didSet { draw() }
    }

    /// The theme in effect, so a theme change redraws the label and the control.
    var theme: CloveTheme? {
        didSet { draw() }
    }

    /// The resolved app language in effect, so a language change redraws the label and control.
    var language: ResolvedAppLanguage = .english {
        didSet { draw() }
    }

    /// Folds the group this header stands for.
    var fold: (GroupID) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        countLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.numberOfLines = 1
        foldButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        foldButton.accessibilityLabel = AppLocalization.string("Collapse group", language: language)
        foldButton.accessibilityIdentifier = "clove.grid.group.fold"
        foldButton.addTarget(self, action: #selector(foldGroup), for: .touchUpInside)
        for view in [countLabel, foldButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
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
        count: Int, group: GroupID, theme: CloveTheme,
        language: ResolvedAppLanguage = .english,
        fold: @escaping (GroupID) -> Void
    ) {
        self.count = count
        self.group = group
        self.theme = theme
        self.language = language
        self.fold = fold
    }

    private func draw() {
        foldButton.accessibilityLabel = AppLocalization.string("Collapse group", language: language)
        guard let group else { return }
        countLabel.text = AppLocalization.format(
            "%lld photos", language: language, Int64(count))
        countLabel.accessibilityIdentifier = "clove.grid.group.count.\(group.rawValue)"
        guard let theme else { return }
        countLabel.textColor = UIColor(theme.tokens.primaryText.color)
        foldButton.tintColor = UIColor(theme.tokens.primaryText.color)
    }

    @objc private func foldGroup() {
        guard let group else { return }
        fold(group)
    }
}
