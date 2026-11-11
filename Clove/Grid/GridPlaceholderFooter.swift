import CloveCore
import SwiftUI
import UIKit

/// One tiled drawing for unread photos. No photo identity or temporary order is assigned.
final class GridPlaceholderFooter: UICollectionReusableView {
    private var count = 0
    private var columns = 3
    private var theme: CloveTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(count: Int, columns: Int, theme: CloveTheme) {
        guard self.count != count || self.columns != columns || self.theme != theme else { return }
        self.count = count
        self.columns = columns
        self.theme = theme
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard count > 0, let theme else { return }
        let spacing: CGFloat = 1.5
        let side = (bounds.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        guard side > 0 else { return }
        let stride = side + spacing
        let rows = (count + columns - 1) / columns
        let firstRow = min(max(Int(floor(rect.minY / stride)), 0), rows)
        let lastRow = min(max(Int(ceil(rect.maxY / stride)), firstRow), rows)
        UIColor(theme.tokens.sheet.color).setFill()
        for row in firstRow..<lastRow {
            for column in 0..<columns where row * columns + column < count {
                UIRectFill(
                    CGRect(
                        x: CGFloat(column) * stride, y: CGFloat(row) * stride, width: side,
                        height: side))
            }
        }
    }
}
