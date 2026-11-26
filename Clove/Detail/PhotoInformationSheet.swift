import CloveCore
import CloveImaging
import SwiftUI

/// Read-only metadata, loaded on demand through the folder session. Missing fields are omitted.
struct PhotoInformationSheet: View {
    enum MarkSegmentTone: Equatable, Sendable {
        case rating
        case reject
        case secondary

        var token: ThemeToken {
            switch self {
            case .rating: .ratingOn
            case .reject: .reject
            case .secondary: .secondaryText
            }
        }
    }

    struct MarkSegment: Equatable, Sendable {
        let text: String
        let tone: MarkSegmentTone
    }

    struct MarksSummary: Equatable, Sendable {
        let segments: [MarkSegment]

        var text: String {
            segments.map(\.text).joined()
        }

        var isNeutral: Bool {
            segments.allSatisfy { $0.tone == .secondary }
        }
    }

    let browsing: BrowsingModel
    let photo: GridPhoto
    private let explicitGroupMemberCount: Int?
    private let usesExplicitGroupMemberCount: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @State private var information: PhotoInformation?
    @State private var isLoading = true

    init(browsing: BrowsingModel, photo: GridPhoto) {
        self.browsing = browsing
        self.photo = photo
        self.explicitGroupMemberCount = nil
        self.usesExplicitGroupMemberCount = false
    }

    init(browsing: BrowsingModel, photo: GridPhoto, groupMemberCount: Int?) {
        self.browsing = browsing
        self.photo = photo
        self.explicitGroupMemberCount = groupMemberCount
        self.usesExplicitGroupMemberCount = true
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().accessibilityLabel(
                        AppLocalization.string("Loading photo information", language: language))
                } else if let information {
                    capture(information.image)
                    Section(AppLocalization.string("File", language: language)) {
                        if !information.relativeFolder.isEmpty {
                            row(
                                AppLocalization.string("Folder", language: language),
                                information.relativeFolder)
                        }
                        if let size = sizeText(information.image) {
                            row(AppLocalization.string("Size", language: language), size)
                        }
                        row(
                            AppLocalization.string("Marks", language: language), "",
                            trailing: marksTrailing()
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("clove.detail.info.marks")
                        if let keywords = Self.keywordsText(for: currentMarks) {
                            row(AppLocalization.string("Keywords", language: language), keywords)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("clove.detail.info.keywords")
                        }
                    }
                    .listRowBackground(theme.tokens.card.color)
                }
                if FolderPreparationAccessibility.shouldShowInfoSheetPreparationRow(
                    for: browsing.preparationStatus,
                    isGroupingInProgress: browsing.isGroupingInProgress)
                {
                    folderPreparationSection
                }
            }
            .environment(\.defaultMinListRowHeight, 36)
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                leadingHeaderToolbarItem
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done", language: language)) { dismiss() }
                        .foregroundStyle(Color.clove.accent)
                        .accessibilityIdentifier("clove.detail.info.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: photo.id) {
            information = nil
            isLoading = true
            let result = await browsing.information(for: photo.id)
            guard !Task.isCancelled else { return }
            information = result
            isLoading = false
        }
        .accessibilityIdentifier("clove.detail.info.sheet")
    }

    private var currentMarks: PhotoMarks {
        browsing.state.folder != nil ? browsing.shownMarks(for: photo.id) : photo.marks
    }

    private var resolvedGroupMemberCount: Int? {
        if usesExplicitGroupMemberCount {
            guard let explicitGroupMemberCount, explicitGroupMemberCount >= 2 else { return nil }
            return explicitGroupMemberCount
        }
        guard browsing.similarGroupsEnabled, !browsing.isScanning else { return nil }
        return DetailTimeline(
            photos: browsing.photos,
            groups: browsing.groups,
            groupsEnabled: true
        )
        .activeGroup(containing: photo.id)?.visibleMembers.count
    }

    private var folderPreparationSection: some View {
        Section {
            NavigationLink {
                FolderPreparationDetails(
                    browsing: browsing,
                    showsDoneButton: false,
                    embedsNavigationStack: false,
                    onDone: { dismiss() })
            } label: {
                HStack(spacing: 10) {
                    preparationRowIcon
                    Text(AppLocalization.string("Folder preparation", language: language))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(
                        FolderPreparationAccessibility.infoSheetSummaryText(
                            for: browsing.preparationStatus,
                            isGroupingInProgress: browsing.isGroupingInProgress,
                            groupingProgress: browsing.groupingProgress,
                            language: language)
                    )
                    .foregroundStyle(preparationSummaryColour)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            }
            .listRowBackground(theme.tokens.card.color)
            .accessibilityIdentifier("clove.detail.info.preparation")
        }
    }

    @ViewBuilder
    private var preparationRowIcon: some View {
        let status = browsing.preparationStatus
        if let reason = status.waitingReason {
            Image(systemName: FolderPreparationAccessibility.waitingSymbol(for: reason))
                .foregroundStyle(Color.clove.text.secondary)
                .accessibilityHidden(true)
        } else if !status.issues.isEmpty,
            !FolderPreparationAccessibility.isActive(
                for: status, isGroupingInProgress: browsing.isGroupingInProgress)
        {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Color.clove.status.failed)
                .accessibilityHidden(true)
        } else {
            InlineFolderPreparationBar(
                browsing: browsing,
                identifier: "clove.detail.info.preparation.progress",
                width: 28,
                height: 3)
        }
    }

    private var preparationSummaryColour: CloveColour {
        let status = browsing.preparationStatus
        if status.waitingReason == nil,
            !status.issues.isEmpty,
            !FolderPreparationAccessibility.isActive(
                for: status, isGroupingInProgress: browsing.isGroupingInProgress)
        {
            return Color.clove.status.failed
        }
        return Color.clove.text.secondary
    }

    @ToolbarContentBuilder
    private var leadingHeaderToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                headerTitleView
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                headerTitleView
            }
        }
    }

    private var headerTitleView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(photo.fileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if let subtitle = Self.headerSubtitle(
                companions: information?.companions ?? [],
                groupMemberCount: resolvedGroupMemberCount,
                language: language)
            {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("clove.detail.info.subtitle")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    static func headerSubtitle(
        companions: [String],
        groupMemberCount: Int?,
        language: ResolvedAppLanguage
    ) -> String? {
        var parts: [String] = []
        if !companions.isEmpty {
            parts.append("+ " + companions.joined(separator: " · "))
        }
        if let groupMemberCount, groupMemberCount >= 2 {
            parts.append(
                AppLocalization.format(
                    "Burst of %lld", language: language, Int64(groupMemberCount)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private func capture(_ image: ImageInformation?) -> some View {
        if let image,
            image.captureWallTime != nil || image.camera != nil || image.bodySerial != nil
                || image.lens != nil || exposureText(image) != nil
        {
            Section(AppLocalization.string("Capture", language: language)) {
                if let taken = takenText(image) {
                    row(AppLocalization.string("Taken", language: language), taken)
                }
                let camera = [image.camera, image.bodySerial].compactMap { $0 }.joined(
                    separator: " · ")
                if !camera.isEmpty {
                    row(AppLocalization.string("Camera", language: language), camera)
                }
                if let lens = image.lens {
                    row(AppLocalization.string("Lens", language: language), lens)
                }
                if let exposure = exposureText(image) {
                    row(AppLocalization.string("Exposure", language: language), exposure)
                }
            }
            .listRowBackground(theme.tokens.card.color)
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        row(name, value, trailing: nil)
    }

    private func row(
        _ name: String, _ value: String, trailing marks: Text?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
            Spacer(minLength: 8)
            if let marks {
                marks
                    .multilineTextAlignment(.trailing)
            } else {
                Text(value).foregroundStyle(Color.clove.text.secondary).multilineTextAlignment(
                    .trailing)
            }
        }
        .font(.subheadline)
        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }

    /// The frame's marks column: only star glyphs in `rating/on`, Reject in `reject`, and
    /// separators, colour label name, keyword-only count, `"Unmarked"`, and storage source in
    /// `text/secondary` (handoff screens.md §03 Info sheet, screens/03-detail-info-sheet.png).
    private func marksTrailing() -> Text {
        let segments = Self.marksRowSegments(
            for: currentMarks,
            usesSidecar: information?.usesSidecar == true,
            language: language)
        var attributed = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            part.foregroundColor = theme.tokens[segment.tone.token].color
            attributed.append(part)
        }
        return Text(attributed)
    }

    static func keywordsText(for marks: PhotoMarks) -> String? {
        marks.keywords.isEmpty ? nil : marks.keywords.joined(separator: ", ")
    }

    static func marksSummary(for marks: PhotoMarks, language: ResolvedAppLanguage) -> MarksSummary {
        var segments: [MarkSegment] = []

        func appendSegment(_ text: String, tone: MarkSegmentTone) {
            if !segments.isEmpty {
                segments.append(MarkSegment(text: " · ", tone: .secondary))
            }
            segments.append(MarkSegment(text: text, tone: tone))
        }

        if let stars = marks.rating.starCount {
            appendSegment(String(repeating: "★", count: stars), tone: .rating)
        }
        if let colour = marks.label.colour {
            appendSegment(AppLocalization.colourName(colour, language: language), tone: .secondary)
        } else if !marks.label.isClear {
            appendSegment(marks.label.rawValue, tone: .secondary)
        }
        if marks.isRejected {
            appendSegment(AppLocalization.string("Rejected", language: language), tone: .reject)
        }
        if !segments.isEmpty {
            return MarksSummary(segments: segments)
        }
        if !marks.keywords.isEmpty {
            return MarksSummary(segments: [
                MarkSegment(
                    text: AppLocalization.format(
                        "%lld keywords", language: language, Int64(marks.keywords.count)),
                    tone: .secondary)
            ])
        }
        return MarksSummary(segments: [
            MarkSegment(
                text: AppLocalization.string("Unmarked", language: language), tone: .secondary)
        ])
    }

    static func marksRowSegments(
        for marks: PhotoMarks,
        usesSidecar: Bool,
        language: ResolvedAppLanguage
    ) -> [MarkSegment] {
        let summary = marksSummary(for: marks, language: language)
        let storage = AppLocalization.string(
            usesSidecar ? "XMP sidecar" : "Clove only",
            language: language)
        return summary.segments + [
            MarkSegment(text: " · ", tone: .secondary),
            MarkSegment(text: storage, tone: .secondary),
        ]
    }

    private func takenText(_ image: ImageInformation) -> String? {
        guard let date = image.captureWallTime else { return nil }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        // EXIF's wall time is a zone-free surrogate, not a UTC instant to shift into local time.
        formatter.timeZone = .gmt
        if let precision = image.subseconds {
            // Place the EXIF digits next to seconds, before a locale's AM/PM suffix.
            formatter.dateFormat = formatter.dateFormat.replacingOccurrences(
                of: "ss", with: "ss'.\(precision)'")
        }
        return formatter.string(from: date)
    }

    private func exposureText(_ image: ImageInformation) -> String? {
        ExposureFormatting.text(for: image)
    }

    private func sizeText(_ image: ImageInformation?) -> String? {
        guard let image else { return nil }
        var parts: [String] = []
        if let width = image.pixelWidth, let height = image.pixelHeight {
            parts.append("\(width) × \(height)")
        }
        if let bytes = image.fileSizeBytes {
            parts.append(bytes.formatted(.byteCount(style: .file).locale(language.locale)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
