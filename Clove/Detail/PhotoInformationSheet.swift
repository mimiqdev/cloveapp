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
                        if !information.companions.isEmpty {
                            row("Companions", information.companions.joined(separator: " · "))
                        }
                        if let size = sizeText(information.image) { row("Size", size) }
                        row("Marks", MarkSummary.text(for: browsing.cullingMarks(for: photo)))
                        row("Storage", information.usesSidecar ? "XMP sidecar" : "Clove only")
                        HStack {
                            Text("Status")
                            Spacer()
                            SaveStatusIndicator(
                                browsing: browsing, identifierPrefix: "clove.detail.info.saveState",
                                photo: photo.id)
                        }
                    }
                    .listRowBackground(theme.tokens.card.color)
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.clove.text.primary)
            .background(Color.clove.surface.sheet)
            .navigationTitle(photo.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Color.clove.text.secondary).multilineTextAlignment(
                .trailing)
        }
        .font(.subheadline)
    }

    private func takenText(_ image: ImageInformation) -> String? {
        guard let date = image.captureWallTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        // EXIF's wall time is a zone-free surrogate, not a UTC instant to shift into local time.
        formatter.timeZone = .gmt
        let precision = image.subseconds.map { ".\($0)" } ?? ""
        return formatter.string(from: date) + precision
    }

    private func exposureText(_ image: ImageInformation) -> String? {
        var parts: [String] = []
        if let seconds = image.exposureSeconds {
            parts.append(
                seconds < 1
                    ? "1/\((1 / seconds).formatted(.number.precision(.fractionLength(0)))) s"
                    : "\(seconds.formatted()) s")
        }
        if let aperture = image.aperture { parts.append("ƒ/\(aperture.formatted())") }
        if let iso = image.iso { parts.append("ISO \(iso.formatted())") }
        if let focal = image.focalLengthMillimetres { parts.append("\(focal.formatted()) mm") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
