import CloveCore
import CloveImaging
import SwiftUI

/// Read-only metadata, loaded on demand through the folder session. Missing fields are omitted.
struct PhotoInformationSheet: View {
    let browsing: BrowsingModel
    let photo: GridPhoto
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @State private var information: PhotoInformation?
    @State private var isLoading = true

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
            }
            .environment(\.defaultMinListRowHeight, 36)
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .navigationTitle(photo.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(photo.fileName).font(.headline).lineLimit(1)
                        if let information, !information.companions.isEmpty {
                            Text("+ " + information.companions.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Color.clove.text.secondary)
                                .lineLimit(1)
                        }
                    }
                }
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
        _ name: String, _ value: String, trailing marks: (spacing: CGFloat, content: Text)?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
            Spacer(minLength: 8)
            if let marks {
                HStack(spacing: marks.spacing) {
                    marks.content
                    Text("·").foregroundStyle(Color.clove.text.secondary)
                    Text(
                        AppLocalization.string(
                            information?.usesSidecar == true ? "XMP sidecar" : "Clove only",
                            language: language)
                    )
                    .foregroundStyle(Color.clove.text.secondary)
                }
            } else {
                Text(value).foregroundStyle(Color.clove.text.secondary).multilineTextAlignment(
                    .trailing)
            }
        }
        .font(.subheadline)
        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }

    /// The frame's marks column: filled stars in `rating/on`, the label as its colour name, and
    /// Reject as ✕ glyphs (handoff screens.md §03 Info sheet, screens/03-detail-info-sheet.png).
    /// When a photo carries only keywords, shows the keyword count in neutral secondary text
    /// instead of "Unmarked".
    private func marksTrailing() -> (spacing: CGFloat, content: Text) {
        let summary = Self.marksSummary(for: currentMarks, language: language)
        let colour = summary.isNeutral ? Color.clove.text.secondary : Color.clove.rating.on
        return (6, Text(summary.text).foregroundStyle(colour))
    }

    static func keywordsText(for marks: PhotoMarks) -> String? {
        marks.keywords.isEmpty ? nil : marks.keywords.joined(separator: ", ")
    }

    static func marksSummary(for marks: PhotoMarks, language: ResolvedAppLanguage) -> (
        text: String, isNeutral: Bool
    ) {
        var parts: [String] = []
        if let stars = marks.rating.starCount {
            parts.append(String(repeating: "★", count: stars))
        }
        if let colour = marks.label.colour {
            parts.append(AppLocalization.colourName(colour, language: language))
        } else if !marks.label.isClear {
            parts.append(marks.label.rawValue)
        }
        if marks.isRejected {
            parts.append("✕")
        }
        if !parts.isEmpty {
            return (parts.joined(separator: " · "), false)
        }
        if !marks.keywords.isEmpty {
            return (
                AppLocalization.format(
                    "%lld keywords", language: language, Int64(marks.keywords.count)),
                true
            )
        }
        return (AppLocalization.string("Unmarked", language: language), false)
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
