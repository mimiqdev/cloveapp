import CloveCore
import SwiftUI
import UIKit

/// Plain, noninteractive squares for discovered photos still waiting for metadata.
/// They are a footer rather than photo items, so unread photos never acquire a temporary order.
final class GridPlaceholderFooter: UICollectionReusableView {
    private var hosted: UIView?

    func configure(count: Int, columns: Int, theme: CloveTheme) {
        hosted?.removeFromSuperview()
        let content = UIHostingConfiguration {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: columns),
                spacing: 1.5
            ) {
                ForEach(0..<count, id: \.self) { _ in
                    Rectangle().fill(Color.clove.surface.card).aspectRatio(1, contentMode: .fit)
                }
            }
            .environment(\.cloveTheme, theme)
            .accessibilityHidden(true)
        }
        .margins(.all, 0)
        .makeContentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hosted = content
        isUserInteractionEnabled = false
    }
}
