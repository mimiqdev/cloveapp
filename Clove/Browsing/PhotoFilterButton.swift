import CloveCore
import SwiftUI
import UIKit

/// Shared Filter toolbar menu reused by Grid and Detail across all devices.
struct PhotoFilterButton: View {
    let browsing: BrowsingModel
    var identifierPrefix = "clove.grid.filter"
    var onMoreFilters: (() -> Void)? = nil

    @Environment(\.appLanguage) private var language
    @Environment(\.displayScale) private var displayScale
    @Environment(\.self) private var environment

    private static let standardLabels = LabelColour.allCases.filter { !$0.isExtended }

    private var hasFilter: Bool { browsing.hasActiveFilter }

    private var minimumRating: Rating {
        if case .ratedAtLeast(let rating) = browsing.state.filter { return rating }
        return .unrated
    }

    var body: some View {
        let filterLabel = AppLocalization.string("Filter", language: language)
        let activeValue = AppLocalization.string(hasFilter ? "On" : "Off", language: language)
        Menu {
            filterMenuContent
        } label: {
            Label(filterLabel, systemImage: "line.3.horizontal.decrease")
                .accessibilityLabel(filterLabel)
                .accessibilityValue(activeValue)
                .accessibilityAddTraits(hasFilter ? .isSelected : [])
        }
        .menuOrder(.fixed)
        .tint(hasFilter ? Color.clove.accent : Color.clove.text.primary)
        .help(filterLabel)
        .accessibilityLabel(filterLabel)
        .accessibilityValue(activeValue)
        .accessibilityAddTraits(hasFilter ? .isSelected : [])
        .accessibilityIdentifier(identifierPrefix)
    }

    @ViewBuilder
    private var filterMenuContent: some View {
        let counts = browsing.sidebarCounts

        Section {
            statusRow(
                AppLocalization.string("All", language: language),
                count: counts.all,
                filter: .all,
                identifier: "all")
            statusRow(
                AppLocalization.string("Unmarked", language: language),
                count: counts.unmarked,
                filter: .unmarked,
                identifier: "unmarked")
            statusRow(
                AppLocalization.string("Rejected", language: language),
                count: counts.rejected,
                filter: .rejected,
                identifier: "rejected")
        }

        Section(AppLocalization.string("Rating ≥", language: language)) {
            ControlGroup {
                ForEach(EnabledRatings.all.levels, id: \.rawValue) { level in
                    let stars = level.starCount ?? 0
                    let isSelected = browsing.labelFilter == nil && minimumRating == level
                    let title = AppLocalization.format("★%lld+", language: language, Int64(stars))
                    Toggle(
                        isOn: Binding(
                            get: { isSelected },
                            set: { _ in
                                browsing.setFilter(isSelected ? .all : .ratedAtLeast(level))
                            }
                        )
                    ) {
                        Label {
                            Text(title)
                        } icon: {
                            Image(uiImage: ratingChipImage(title: title, selected: isSelected))
                        }
                    }
                    .accessibilityLabel(AppLocalization.starCount(stars, language: language))
                    .accessibilityIdentifier("\(identifierPrefix).stars.\(level.rawValue)")
                }
            }
            .controlGroupStyle(.palette)
        }

        Section(AppLocalization.string("Label", language: language)) {
            ControlGroup {
                ForEach(Self.standardLabels, id: \.self) { label in
                    let isSelected = browsing.labelFilter == label
                    let labelTitle = AppLocalization.colourName(label, language: language)
                    Toggle(
                        isOn: Binding(
                            get: { isSelected },
                            set: { _ in
                                if isSelected {
                                    browsing.setFilter(.all)
                                } else {
                                    browsing.setLabelFilter(label)
                                }
                            }
                        )
                    ) {
                        Label {
                            Text(labelTitle)
                        } icon: {
                            Image(uiImage: labelDotImage(for: label, selected: isSelected))
                        }
                    }
                    .accessibilityLabel(
                        AppLocalization.format("Label, %@", language: language, labelTitle)
                    )
                    .accessibilityIdentifier(
                        "\(identifierPrefix).label.\(label.rawValue.lowercased())")
                }
            }
            .controlGroupStyle(.palette)
        }

        if let onMoreFilters,
            browsing.metadataFilterOptions.hasAnyDimension || !browsing.metadataFilter.isEmpty
        {
            Section {
                moreFiltersButton(action: onMoreFilters)
                    .tint(
                        browsing.metadataFilter.isEmpty
                            ? Color.clove.text.primary : Color.clove.accent
                    )
                    .accessibilityIdentifier("\(identifierPrefix).more")
            }
        }
    }

    @ViewBuilder
    private func moreFiltersButton(action: @escaping () -> Void) -> some View {
        let title = AppLocalization.string("More filters", language: language)
        if browsing.metadataFilter.isEmpty {
            Button(action: action) {
                Label(title, systemImage: "slider.horizontal.3")
            }
        } else {
            let activeText = AppLocalization.format(
                "%lld filters", language: language,
                Int64(browsing.metadataFilter.activeCount))
            Button(action: action) {
                Text(title)
                Text(activeText)
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    private func statusRow(
        _ name: String, count: Int, filter: PhotoFilter, identifier: String
    ) -> some View {
        let isSelected = browsing.state.filter == filter && browsing.labelFilter == nil
        let countText = count.formatted(.number.locale(language.locale))
        return Toggle(
            isOn: Binding(
                get: { isSelected },
                set: { _ in browsing.setFilter(filter) }
            )
        ) {
            Text(name)
            Text(countText)
        }
        .accessibilityIdentifier("\(identifierPrefix).\(identifier)")
    }

    private func ratingChipImage(title: String, selected: Bool) -> UIImage {
        let size = CGSize(width: 38, height: 28)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        let textColor =
            selected
            ? UIColor(Color.clove.accent.resolve(in: environment))
            : UIColor(Color.clove.text.primary.resolve(in: environment))
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: selected ? .bold : .semibold),
                .foregroundColor: textColor,
            ]
            let attributed = NSAttributedString(string: title, attributes: attributes)
            let textSize = attributed.size()
            let textOrigin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2)
            attributed.draw(at: textOrigin)
        }
        .withRenderingMode(.alwaysOriginal)
    }

    private func labelDotImage(for label: LabelColour, selected: Bool) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        let dotColor = UIColor(Color.clove.label.colour(for: label).resolve(in: environment))
        let ringColor = UIColor(Color.clove.text.primary.resolve(in: environment))
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let dotRect = CGRect(x: 4, y: 4, width: 14, height: 14)
            cg.setFillColor(dotColor.cgColor)
            cg.fillEllipse(in: dotRect)
            if selected {
                cg.setStrokeColor(ringColor.cgColor)
                cg.setLineWidth(1.75)
                cg.strokeEllipse(in: CGRect(x: 1.25, y: 1.25, width: 19.5, height: 19.5))
            }
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
