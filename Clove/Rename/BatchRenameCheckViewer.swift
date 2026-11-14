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
    @State private var pixels: RenameCheckImages
    @State private var scale: CGFloat = 1
    @State private var nativeAnchor: UnitPoint?
    @State private var size: CGSize = .zero
    @State private var command: DetailZoomCommand?
    @State private var commandID = 0
    @State private var windowID = UUID()
    @State private var feedback = DetailSwipeFeedback()

    private var identity: PhotoIdentity { current ?? initialPhoto }
    private var index: Int { flow.order.firstIndex { $0.id == identity } ?? 0 }
    private var photo: GridPhoto { flow.order[index] }
    private var shown: DetailImage? { pixels.shown }
    private var placeholder: CGImage? { pixels.placeholder }

    init(flow: BatchRenameFlow, initialPhoto: PhotoIdentity) {
        self.flow = flow
        self.initialPhoto = initialPhoto
        _pixels = State(initialValue: RenameCheckImages(source: flow.browsing.detailImages))
    }
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
                doubleTapZoomEnabled: true, rules: rules, currentRating: .unrated,
                feedback: feedback,
                onZoomChange: { value in
                    nativeAnchor = nil
                    scale = value
                },
                onChromeToggle: {},
                onStep: { step($0) },
                onDoubleTap: { anchor in doubleTap(anchor) }, onMarkingSwipe: { _ in },
                onSwipeBegin: {}, hasPrevious: index > 0, hasNext: index + 1 < flow.order.count
            )
            .accessibilityLabel(photo.fileName)
            .accessibilityValue(scale > DetailFitScale.tolerance ? "Zoomed" : "Fit")
            .accessibilityIdentifier("clove.rename.viewer.preview")
            .accessibilityAction(named: "Previous photo") { step(-1) }
            .accessibilityAction(named: "Next photo") { step(1) }
            .overlay {
                if pixels.unavailable {
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.rename.viewer")
        .task(id: identity) { await load() }
        .onChange(of: scale > DetailFitScale.tolerance) { _, zoomed in
            pixels.setZoomed(zoomed)
        }
        .onChange(of: shown?.fullResolutionPixels) { _, _ in
            if let nativeAnchor, scale > DetailFitScale.tolerance { zoomToNative(at: nativeAnchor) }
        }
        .onDisappear { pixels.close() }
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
        nativeAnchor = nil
        scale = 1
        commandID += 1
        command = DetailZoomCommand(id: commandID, kind: .fit)
        await pixels.load(window, thumbnails: flow.browsing.thumbnails)
    }

    private func step(_ offset: Int) {
        let next = index + offset
        guard flow.order.indices.contains(next) else { return }
        current = flow.order[next].id
    }

    private func doubleTap(_ anchor: UnitPoint) {
        if scale > DetailFitScale.tolerance {
            nativeAnchor = nil
            scale = 1
            commandID += 1
            command = DetailZoomCommand(id: commandID, kind: .fit)
        } else {
            nativeAnchor = anchor
            zoomToNative(at: anchor)
        }
    }

    private func zoomToNative(at anchor: UnitPoint) {
        let bitmap = shown?.image ?? placeholder
        let shownSize = bitmap.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        scale =
            DetailZoom.fullResolutionTarget(
                nativePixels: shown?.fullResolutionPixels,
                shownPixels: shownSize, viewSize: size, screenScale: displayScale)
            ?? DetailZoom.inspectionScale
        commandID += 1
        command = DetailZoomCommand(id: commandID, kind: .scale(scale, anchor: anchor))
    }
}
