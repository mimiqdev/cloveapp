import CloveCore
import CloveImaging
import SwiftUI

/// Read-only metadata, loaded on demand through the folder session. Missing fields are omitted.
struct PhotoInformationSheet: View {
    let browsing: BrowsingModel
    let photo: GridPhoto
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @State private var information: PhotoInformation?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().accessibilityLabel("Loading photo information")
                } else if let information {
                    capture(information.image)
                    Section("File") {
                        if !information.relativeFolder.isEmpty {
                            row("Folder", information.relativeFolder)
                        }
                        if let size = sizeText(information.image) { row("Size", size) }
                        row("Marks", "", trailing: marksTrailing(information))
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
                    Button("Done") { dismiss() }
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

    @ViewBuilder private func capture(_ image: ImageInformation?) -> some View {
        if let image,
            image.captureWallTime != nil || image.camera != nil || image.bodySerial != nil
                || image.lens != nil || exposureText(image) != nil
        {
            Section("Capture") {
                if let taken = takenText(image) { row("Taken", taken) }
                let camera = [image.camera, image.bodySerial].compactMap { $0 }.joined(
                    separator: " · ")
                if !camera.isEmpty { row("Camera", camera) }
                if let lens = image.lens { row("Lens", lens) }
                if let exposure = exposureText(image) { row("Exposure", exposure) }
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
                        information?.usesSidecar == true ? "XMP sidecar" : "Clove only"
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
    private func marksTrailing(_ information: PhotoInformation) -> (spacing: CGFloat, content: Text)
    {
        var parts: [String] = []
        if let stars = photo.marks.rating.starCount {
            parts.append(String(repeating: "★", count: stars))
        }
        if let colour = photo.marks.label.colour {
            parts.append(colour.rawValue)
        } else if !photo.marks.label.isClear {
            parts.append(photo.marks.label.rawValue)
        }
        if photo.marks.isRejected {
            parts.append("✕")
        }
        let text = parts.isEmpty ? Text("Unmarked") : Text(parts.joined(separator: " · "))
        return (6, text.foregroundStyle(Color.clove.rating.on))
    }

    private func takenText(_ image: ImageInformation) -> String? {
        guard let date = image.captureWallTime else { return nil }
        let formatter = DateFormatter()
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
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
