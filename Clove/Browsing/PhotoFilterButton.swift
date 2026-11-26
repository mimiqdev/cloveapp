import CloveCore
import SwiftUI

/// Shared Filter toolbar button and popover menu reused by Grid and Detail across all devices.
///
/// Reuses ``GridFilterSheetHandoff`` so tapping `"More filters"` inside the popover waits until
/// popover dismissal finishes before presenting ``MetadataFilterSheet``.
struct PhotoFilterPopoverButton: View {
    let browsing: BrowsingModel
    var controlSize: ControlSize = .phone
    var identifierPrefix = "clove.grid.filter"
    @Binding var filterHandoff: GridFilterSheetHandoff
    let canPresentMetadataFilters: Bool
    var popoverTrigger: Int = 0
    let onCancelPendingMetadataFilters: () -> Void
    let onCompleteMetadataFiltersHandoff: () -> Void

    @Environment(\.usesSystemBrowsingToolbar) private var usesSystemToolbar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguage) private var language
    @State private var isAnchorReady = false
    @State private var isPopoverContentMounted = false

    private var hasFilter: Bool { browsing.hasActiveFilter }

    private var minimumRating: Rating {
        if case .ratedAtLeast(let rating) = browsing.state.filter { return rating }
        return .unrated
    }

    var body: some View {
        let filterLabel = AppLocalization.string("Filter", language: language)
        let activeValue = AppLocalization.string(hasFilter ? "On" : "Off", language: language)
        if usesSystemToolbar, #available(iOS 27.1, *) {
            SystemToolbarFilterButton(
                filterLabel: filterLabel,
                activeValue: activeValue,
                hasFilter: hasFilter,
                identifierPrefix: identifierPrefix,
                isPresented: popoverBinding,
                onTap: handleTap,
                onAnchorAppear: handleAnchorAppear,
                onAnchorDisappear: handleAnchorDisappear,
                popoverTrigger: popoverTrigger,
                onTrigger: handlePopoverTrigger
            ) {
                popoverContent
            }
        } else {
            GlassIconButton(
                label: filterLabel,
                symbol: "line.3.horizontal.decrease",
                isActive: hasFilter,
                size: controlSize,
                identifier: identifierPrefix,
                action: handleTap
            )
            .popover(
                isPresented: popoverBinding,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                popoverContent
            }
            .onChange(of: popoverTrigger) { _, _ in
                handlePopoverTrigger()
            }
            .onAppear(perform: handleAnchorAppear)
            .onDisappear(perform: handleAnchorDisappear)
        }
    }

    private var popoverBinding: Binding<Bool> {
        Binding(
            get: { filterHandoff.showsFilters && isAnchorReady && scenePhase == .active },
            set: { presented in
                if presented {
                    onCancelPendingMetadataFilters()
                }
                filterHandoff.setFiltersPresented(presented)
            })
    }

    private var popoverContent: some View {
        filterMenu
            .presentationCompactAdaptation(.popover)
            .onAppear {
                isPopoverContentMounted = true
            }
            .onDisappear {
                isPopoverContentMounted = false
                if filterHandoff.showsFilters {
                    filterHandoff.setFiltersPresented(false)
                }
                onCompleteMetadataFiltersHandoff()
            }
    }

    private func handleTap() {
        let isCurrentlyPresented =
            filterHandoff.showsFilters
            && isAnchorReady
            && isPopoverContentMounted
            && scenePhase == .active
        isAnchorReady = true
        onCancelPendingMetadataFilters()
        filterHandoff.setFiltersPresented(!isCurrentlyPresented)
    }

    private func handleAnchorAppear() {
        isAnchorReady = true
    }

    private func handleAnchorDisappear() {
        isAnchorReady = false
        filterHandoff.setFiltersPresented(false)
    }

    private func handlePopoverTrigger() {
        if isAnchorReady, scenePhase == .active {
            onCancelPendingMetadataFilters()
            filterHandoff.setFiltersPresented(true)
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        let counts = browsing.sidebarCounts
        VStack(spacing: 0) {
            filterRow(
                AppLocalization.string("All", language: language), count: counts.all, filter: .all,
                identifier: "all")
            filterRow(
                AppLocalization.string("Unmarked", language: language), count: counts.unmarked,
                filter: .unmarked, identifier: "unmarked")
            filterRow(
                AppLocalization.string("Rejected", language: language), count: counts.rejected,
                filter: .rejected, identifier: "rejected")
            Divider().overlay(Color.clove.separator)
            HStack {
                Text(AppLocalization.string("Rating ≥", language: language))
                Spacer()
                FilterStarRow(rating: minimumRating, identifier: "\(identifierPrefix).stars") {
                    rating in
                    browsing.setFilter(rating == .unrated ? .all : .ratedAtLeast(rating))
                    filterHandoff.setFiltersPresented(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            HStack(spacing: 12) {
                Text(AppLocalization.string("Label", language: language))
                Spacer()
                ForEach(LabelColour.allCases.filter { !$0.isExtended }, id: \.self) { label in
                    Button {
                        browsing.setLabelFilter(label)
                        filterHandoff.setFiltersPresented(false)
                    } label: {
                        Circle().fill(Color.clove.label.colour(for: label))
                            .frame(width: 16, height: 16)
                            .frame(height: 32)
                    }
                    .accessibilityLabel(
                        AppLocalization.format(
                            "Label, %@", language: language,
                            AppLocalization.colourName(label, language: language))
                    )
                    .accessibilityIdentifier(
                        "\(identifierPrefix).label.\(label.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if canPresentMetadataFilters,
                browsing.metadataFilterOptions.hasAnyDimension || !browsing.metadataFilter.isEmpty
            {
                Divider().overlay(Color.clove.separator)
                Button {
                    onCancelPendingMetadataFilters()
                    filterHandoff.requestMetadataFiltersFromPopover(folder: browsing.state.folder)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 16)
                            .foregroundStyle(
                                browsing.metadataFilter.isEmpty
                                    ? Color.clove.text.secondary : Color.clove.accent)
                        Text(AppLocalization.string("More filters", language: language))
                        Spacer()
                        if !browsing.metadataFilter.isEmpty {
                            Text(
                                browsing.metadataFilter.activeCount.formatted(
                                    .number.locale(language.locale))
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.clove.accent, in: Capsule())
                            .accessibilityIdentifier("\(identifierPrefix).more.badge")
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.clove.text.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifierPrefix).more")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.clove.text.primary)
        .frame(width: 280)
        .background(Color.clove.surface.sheet)
    }

    private func filterRow(_ name: String, count: Int, filter: PhotoFilter, identifier: String)
        -> some View
    {
        Button {
            browsing.setFilter(filter)
            filterHandoff.setFiltersPresented(false)
        } label: {
            HStack {
                Image(systemName: "checkmark")
                    .opacity(
                        browsing.state.filter == filter && browsing.labelFilter == nil ? 1 : 0
                    )
                    .frame(width: 16)
                Text(name)
                Spacer()
                Text(count.formatted(.number.locale(language.locale)))
                    .foregroundStyle(Color.clove.text.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(identifierPrefix).\(identifier)")
    }

    /// Runs the deferred yield before presenting ``MetadataFilterSheet`` after popover dismissal.
    @MainActor
    static func scheduleMetadataFiltersHandoff(
        handoffTask: inout Task<Void, Never>?,
        canPresent: @escaping @MainActor () -> Bool,
        consume: @escaping @MainActor () -> Bool,
        present: @escaping @MainActor () -> Void,
        clearTask: @escaping @MainActor () -> Void
    ) {
        guard canPresent() else { return }
        handoffTask?.cancel()
        handoffTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if consume() {
                present()
            }
            clearTask()
        }
    }
}

@available(iOS 27.1, *)
private struct SystemToolbarFilterButton<PopoverContent: View>: View {
    let filterLabel: String
    let activeValue: String
    let hasFilter: Bool
    let identifierPrefix: String
    @Binding var isPresented: Bool
    let onTap: () -> Void
    let onAnchorAppear: () -> Void
    let onAnchorDisappear: () -> Void
    let popoverTrigger: Int
    let onTrigger: () -> Void
    @ViewBuilder let popoverContent: () -> PopoverContent

    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    private var arrowEdge: Edge {
        switch verticalEdge {
        case .leading: .leading
        case .trailing: .trailing
        default: .top
        }
    }

    var body: some View {
        Button(filterLabel, systemImage: "line.3.horizontal.decrease", action: onTap)
            .tint(hasFilter ? Color.clove.accent : Color.clove.text.primary)
            .help(filterLabel)
            .accessibilityLabel(filterLabel)
            .accessibilityValue(activeValue)
            .accessibilityAddTraits(hasFilter ? .isSelected : [])
            .accessibilityIdentifier(identifierPrefix)
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: arrowEdge
            ) {
                popoverContent()
            }
            .onChange(of: popoverTrigger) { _, _ in
                onTrigger()
            }
            .onAppear(perform: onAnchorAppear)
            .onDisappear(perform: onAnchorDisappear)
    }
}
