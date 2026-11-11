import CloveCore
import QuartzCore
import SwiftUI
import UIKit

/// Replicates solid tile layers without a bitmap backing the full unread scroll extent.
/// The layer tree stays fixed: a tile replicated into a row, that row replicated vertically,
/// and one separate tile/replicator for the final partial row. No photo order is assigned.
final class GridPlaceholderFooter: UICollectionReusableView {
    private let fullRows = CAReplicatorLayer()
    private let fullColumns = CAReplicatorLayer()
    private let fullTile = CALayer()
    private let partialColumns = CAReplicatorLayer()
    private let partialTile = CALayer()
    private var count = 0
    private var columns = 3
    private var theme: CloveTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        clipsToBounds = true
        fullColumns.addSublayer(fullTile)
        fullRows.addSublayer(fullColumns)
        partialColumns.addSublayer(partialTile)
        layer.addSublayer(fullRows)
        layer.addSublayer(partialColumns)
        // Rasterizing this hierarchy would recreate a bitmap spanning the whole footer.
        for drawingLayer in [layer, fullRows, fullColumns, fullTile, partialColumns, partialTile] {
            drawingLayer.shouldRasterize = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(count: Int, columns: Int, theme: CloveTheme) {
        guard self.count != count || self.columns != columns || self.theme != theme else { return }
        self.count = count
        self.columns = columns
        self.theme = theme
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let spacing: CGFloat = 1.5
        let side = (bounds.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        guard side > 0, let theme else {
            fullRows.isHidden = true
            partialColumns.isHidden = true
            return
        }
        let stride = side + spacing
        let completeRows = count / columns
        let remainder = count % columns
        let rowBounds = CGRect(x: 0, y: 0, width: bounds.width, height: side)
        let tileBounds = CGRect(x: 0, y: 0, width: side, height: side)
        let fill = UIColor(theme.tokens.sheet.color).cgColor

        fullRows.frame = rowBounds
        fullRows.instanceCount = completeRows
        fullRows.instanceTransform = CATransform3DMakeTranslation(0, stride, 0)
        fullRows.isHidden = completeRows == 0
        fullColumns.frame = rowBounds
        fullColumns.instanceCount = columns
        fullColumns.instanceTransform = CATransform3DMakeTranslation(stride, 0, 0)
        fullTile.frame = tileBounds
        fullTile.backgroundColor = fill

        partialColumns.frame = rowBounds.offsetBy(dx: 0, dy: CGFloat(completeRows) * stride)
        partialColumns.instanceCount = remainder
        partialColumns.instanceTransform = CATransform3DMakeTranslation(stride, 0, 0)
        partialColumns.isHidden = remainder == 0
        partialTile.frame = tileBounds
        partialTile.backgroundColor = fill
    }
}
