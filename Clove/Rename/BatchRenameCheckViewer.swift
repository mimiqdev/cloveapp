import CloveCore
import CloveImaging
import SwiftUI

/// The browsing zoom container, with navigation restricted to the proposed rename order.
struct BatchRenameCheckViewer: View {
    let flow: BatchRenameFlow
    let initialPhoto: PhotoIdentity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var current: PhotoIdentity?
    @State private var shown: DetailImage?
    @State private var placeholder: CGImage?
    @State private var unavailable = false
    @State private var scale: CGFloat = 1
    @State private var size: CGSize = .zero
    @State private var command: DetailZoomCommand?
    @State private var commandID = 0
    @State private var windowID = UUID()
    @State private var feedback = DetailSwipeFeedback()

    private var identity: PhotoIdentity { current ?? initialPhoto }
    private var index: Int { flow.order.firstIndex { $0.id == identity } ?? 0 }
    private var photo: GridPhoto { flow.order[index] }
    private var images: any DetailImageSource { flow.browsing.detailImages }
    private var rules: MarkingInputRules {
        var settings = AppSettings()
        settings.gesturesEnabled = false
        return MarkingInputRules(settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowsingHeader(
                title: photo.fileName, titleIdentifier: "clove.rename.viewer.name",
                back: { dismiss() }
            ) {
                Text("\(index + 1) of \(flow.order.count) · swipe for the next in this order")
                    .accessibilityIdentifier("clove.rename.viewer.position")
            } tools: {
            }
            DetailZoomView(
                image: shown?.image ?? placeholder,
                fullResolutionPixels: shown?.fullResolutionPixels, command: command,
                doubleTapZoomEnabled: true, rules: rules, feedback: feedback,
                onZoomChange: { scale = $0 },
                onEdgeTap: { zone in
                    if zone == .next { step(1) }
                    if zone == .previous { step(-1) }
                },
                onDoubleTap: { anchor in doubleTap(anchor) }, onMarkingSwipe: { _ in },
                onSwipeBegin: {}, hasPrevious: index > 0, hasNext: index + 1 < flow.order.count
            )
            .accessibilityLabel(photo.fileName)
            .accessibilityValue(scale > DetailFitScale.tolerance ? "Zoomed" : "Fit")
            .accessibilityIdentifier("clove.rename.viewer.preview")
            .accessibilityAction(named: "Previous photo") { step(-1) }
            .accessibilityAction(named: "Next photo") { step(1) }
            .overlay {
                if unavailable {
                    Text("No preview available").foregroundStyle(Color.clove.text.secondary)
                }
            }
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                size = $0
            }
        }
        .foregroundStyle(Color.clove.text.primary)
        .background(Color.clove.bg.stage)
        .accessibilityIdentifier("clove.rename.viewer")
        .task(id: identity) { await load() }
        .task(id: scale > DetailFitScale.tolerance) {
            guard scale > DetailFitScale.tolerance else { return }
            let requested = identity
            if case .image(let image) = await images.image(
                for: requested, request: window.request(need: .fullResolution)),
                !Task.isCancelled, requested == identity
            {
                shown = image
            }
        }
        .onDisappear {
            shown = nil
            placeholder = nil
            Task { await images.leave(window: windowID) }
        }
    }

    private var window: DetailPhotoWindow {
        DetailPhotoWindow(
            id: windowID, current: DetailNeighbour(photo: identity, position: index),
            neighbours: [index - 1, index + 1].compactMap { position in
                guard flow.order.indices.contains(position) else { return nil }
                return DetailNeighbour(photo: flow.order[position].id, position: position)
            }, direction: 1, mode: .rawFirst,
            screenPixels: Int(max(size.width, size.height, 1000) * displayScale))
    }

    private func load() async {
        let window = window
        shown = nil
        placeholder = nil
        unavailable = false
        scale = 1
        commandID += 1
        command = DetailZoomCommand(id: commandID, kind: .fit)
        placeholder = await images.placeholder(
            for: window.current.photo, gridThumbnails: flow.browsing.thumbnails)
        guard !Task.isCancelled else { return }
        await images.prepare(window)
        let outcome = await images.image(for: window.current.photo, request: window.request())
        guard !Task.isCancelled else { return }
        if case .image(let image) = outcome {
            shown = image
        } else {
            unavailable = placeholder == nil
        }
        if case .image(let image) = await images.image(
            for: window.current.photo, request: window.request(need: .screenRender)),
            !Task.isCancelled
        {
            shown = image
        }
        guard !Task.isCancelled else { return }
        await images.prefetch(window, renderAhead: true)
    }

    private func step(_ offset: Int) {
        let next = index + offset
        guard flow.order.indices.contains(next) else { return }
        current = flow.order[next].id
    }

    private func doubleTap(_ anchor: UnitPoint) {
        commandID += 1
        if scale > DetailFitScale.tolerance {
            scale = 1
            command = DetailZoomCommand(id: commandID, kind: .fit)
        } else {
            let pixels = shown?.image ?? placeholder
            let shownSize = pixels.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
            scale =
                DetailZoom.fullResolutionTarget(
                    nativePixels: shown?.fullResolutionPixels ?? shownSize,
                    shownPixels: shownSize, viewSize: size, screenScale: displayScale)
                ?? DetailZoom.inspectionScale
            command = DetailZoomCommand(id: commandID, kind: .scale(scale, anchor: anchor))
        }
    }
}
