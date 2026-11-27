import CloveCore
import CloveImaging
import SwiftUI

/// Bridges domain photo formats and display settings into progressive RAW decode tracking.
enum DetailProgressiveDecodeSupport {
    static func resolvedPhotoFormat(fileName: String?, photoSet: PhotoSet?) -> PhotoFormat {
        if let format = photoSet?.primary.format {
            return format
        }
        if let fileName {
            let ext = URL(fileURLWithPath: fileName).pathExtension
            if let format = PhotoFormat(pathExtension: ext) {
                return format
            }
        }
        return .raw
    }

    /// True when the viewport is explicitly inspecting 100% (including unknown-size RAWs waiting
    /// at Fit scale) or manually zoomed to or past native 100%.
    static func isAtOrAboveFullResolution(
        scale: CGFloat,
        zoomModeIsFullResolution: Bool,
        fullResolutionPixels: CGSize?,
        viewSize: CGSize,
        screenScale: CGFloat
    ) -> Bool {
        if zoomModeIsFullResolution { return true }
        guard scale > DetailFitScale.tolerance,
            viewSize.width > 0,
            let pixels = fullResolutionPixels
        else { return false }
        let target = DetailZoom.fullResolutionScale(
            nativePixels: pixels, shownPixels: pixels, viewSize: viewSize,
            screenScale: screenScale)
        return scale >= target * 0.995
    }

    /// True while progressive decode feedback or static `Preview only` applies: at/above 100%,
    /// on an explicit 100% request even before native pixels are known, or while a
    /// `.fullResolution` decode remains in flight above Fit.
    static func showsProgressiveState(
        scale: CGFloat,
        zoomModeIsFullResolution: Bool,
        fullResolutionPixels: CGSize?,
        viewSize: CGSize,
        screenScale: CGFloat,
        isFullResolutionUpgradeInFlight: Bool,
        phase: RawProgressiveDecodePhase
    ) -> Bool {
        if isAtOrAboveFullResolution(
            scale: scale,
            zoomModeIsFullResolution: zoomModeIsFullResolution,
            fullResolutionPixels: fullResolutionPixels,
            viewSize: viewSize,
            screenScale: screenScale)
        {
            return true
        }
        return scale > DetailFitScale.tolerance
            && (isFullResolutionUpgradeInFlight || phase.isInFlight)
    }

    /// True when zoom adjustments above Fit should keep existing progressive decode state intact
    /// rather than clearing it (resets only below 100% once no `.fullResolution` upgrade runs).
    static func shouldRetainProgressiveDecodeAboveFit(
        scale: CGFloat,
        zoomModeIsFullResolution: Bool,
        fullResolutionPixels: CGSize?,
        viewSize: CGSize,
        screenScale: CGFloat,
        isFullResolutionUpgradeInFlight: Bool
    ) -> Bool {
        guard zoomModeIsFullResolution || scale > DetailFitScale.tolerance else { return false }
        if isFullResolutionUpgradeInFlight { return true }
        return isAtOrAboveFullResolution(
            scale: scale,
            zoomModeIsFullResolution: zoomModeIsFullResolution,
            fullResolutionPixels: fullResolutionPixels,
            viewSize: viewSize,
            screenScale: screenScale)
    }

    /// Resolves the zoom readout text, displaying `"100%"` while an explicit full-resolution
    /// decode or fallback state is active even before native dimensions allow zooming past Fit.
    static func zoomLabelText(
        scale: CGFloat,
        scaledZoomText: String,
        fitText: String?,
        zoomModeIsFullResolution: Bool,
        isFullResolutionUpgradeInFlight: Bool,
        phase: RawProgressiveDecodePhase,
        language: ResolvedAppLanguage
    ) -> String? {
        if scale > DetailFitScale.tolerance {
            return scaledZoomText
        }
        if zoomModeIsFullResolution && (isFullResolutionUpgradeInFlight || phase != .idle) {
            return AppLocalization.format("%lld%%", language: language, Int64(100))
        }
        return fitText
    }

    static func eligibility(
        fileName: String?,
        photoSet: PhotoSet?,
        displayMode: PhotoDisplayMode,
        shown: DetailImage?,
        isPreviewOnly: Bool,
        isLocationLost: Bool
    ) -> RawProgressiveDecodeEligibility {
        let primaryFormat = resolvedPhotoFormat(fileName: fileName, photoSet: photoSet)
        let hasCameraCompanion =
            photoSet.map { $0.jpegCompanion != nil || $0.heifCompanion != nil } ?? false
        return RawProgressiveDecodeEligibility(
            primaryFormat: primaryFormat,
            hasCameraCompanion: hasCameraCompanion,
            displayMode: displayMode,
            shownHasRAW: shown?.hasRAW ?? false,
            shownIsNativeRAW: shown?.quality == .nativeRAW,
            shownIsScreenRAW: shown?.quality == .screenRAW,
            shownIsBestAvailable: shown?.isBestAvailable ?? false,
            isPreviewOnly: isPreviewOnly,
            isLocationLost: isLocationLost
        )
    }

    @MainActor
    @discardableResult
    static func syncAtFullResolution(
        controller: RawProgressiveDecodeController,
        photoID: PhotoIdentity,
        fileName: String?,
        photoSet: PhotoSet?,
        displayMode: PhotoDisplayMode,
        shown: DetailImage?,
        isPreviewOnly: Bool,
        isLocationLost: Bool,
        startingUpgrade: Bool
    ) -> RawProgressiveDecodeToken? {
        let eligibility = eligibility(
            fileName: fileName,
            photoSet: photoSet,
            displayMode: displayMode,
            shown: shown,
            isPreviewOnly: isPreviewOnly,
            isLocationLost: isLocationLost
        )
        if eligibility.shouldShowStaticPreviewOnly {
            controller.enterPreviewOnly()
            return nil
        }
        if startingUpgrade, eligibility.shouldTrackFullResolutionUpgrade {
            return controller.beginUpgrade(for: photoID)
        }
        if let shown, shown.quality == .nativeRAW || shown.isBestAvailable {
            controller.completeIfTracking(photoID: photoID)
            if controller.phase == .previewOnly {
                controller.reset()
            }
        } else if !eligibility.shouldTrackFullResolutionUpgrade, controller.phase == .previewOnly {
            controller.reset()
        }
        return nil
    }

    @MainActor
    static func settle(
        controller: RawProgressiveDecodeController,
        token: RawProgressiveDecodeToken?,
        outcome: DetailImageOutcome,
        photoID: PhotoIdentity,
        fileName: String?,
        photoSet: PhotoSet?,
        isLocationLost: Bool
    ) {
        let primaryFormat = resolvedPhotoFormat(fileName: fileName, photoSet: photoSet)
        switch outcome {
        case .image(let image):
            let isRawPreviewLimitation =
                image.limitation == .rawRenderFailed
                || (primaryFormat == .raw && image.limitation == .noHigherResolution
                    && !image.isBestAvailable)
            if isRawPreviewLimitation {
                if let token {
                    controller.fail(token: token)
                } else {
                    controller.enterPreviewOnly()
                }
            } else if let token {
                controller.complete(token: token)
            } else {
                controller.completeIfTracking(photoID: photoID)
            }
        case .unavailable:
            if primaryFormat == .raw || isLocationLost {
                if let token {
                    controller.fail(token: token)
                } else {
                    controller.enterPreviewOnly()
                }
            } else if let token {
                controller.cancel(token: token)
            }
        case .deferred:
            if let token {
                controller.cancel(token: token)
            }
        }
    }
}

/// Pure presentation value describing visible segments and accessibility metadata for zoom readouts.
struct DetailZoomReadoutPresentation: Equatable, Sendable {
    let visiblePrefix: String?
    let primaryZoomText: String?
    let trailingStatusText: String?
    let visualPhase: RawProgressiveDecodePhase
    let showsSpinner: Bool
    let accessibilityLabel: String
    let accessibilityValue: String?

    init(
        prefixText: String?,
        accessiblePrefixText: String? = nil,
        zoomText: String?,
        showsProgressiveState: Bool,
        phase: RawProgressiveDecodePhase,
        language: ResolvedAppLanguage
    ) {
        let resolvedAccessiblePrefix = accessiblePrefixText ?? prefixText
        let clampedPhase: RawProgressiveDecodePhase =
            (zoomText != nil && showsProgressiveState && phase != .gating) ? phase : .idle

        self.visualPhase = clampedPhase
        self.visiblePrefix = prefixText

        switch clampedPhase {
        case .idle, .gating:
            self.primaryZoomText = zoomText
            self.trailingStatusText = nil
            self.showsSpinner = false
            self.accessibilityLabel = [resolvedAccessiblePrefix, zoomText]
                .compactMap { $0 }
                .joined(separator: " · ")
            self.accessibilityValue = nil

        case .decodingPreview:
            let previewWord = AppLocalization.string("Preview", language: language)
            self.primaryZoomText = zoomText
            self.trailingStatusText = previewWord
            self.showsSpinner = true
            self.accessibilityLabel = [resolvedAccessiblePrefix, zoomText]
                .compactMap { $0 }
                .joined(separator: " · ")
            self.accessibilityValue = previewWord

        case .previewOnly:
            let previewOnlyWord = AppLocalization.string("Preview only", language: language)
            self.primaryZoomText = nil
            self.trailingStatusText = previewOnlyWord
            self.showsSpinner = false
            self.accessibilityLabel = [resolvedAccessiblePrefix, previewOnlyWord]
                .compactMap { $0 }
                .joined(separator: " · ")
            self.accessibilityValue = nil
        }
    }

    /// Plain text representation without inline spinner, useful for presentation assertions and empty
    /// checks.
    var combinedVisibleText: String? {
        let suffixText: String?
        if let primaryZoomText, let trailingStatusText {
            suffixText = "\(primaryZoomText) · \(trailingStatusText)"
        } else {
            suffixText = primaryZoomText ?? trailingStatusText
        }
        let parts = [visiblePrefix, suffixText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Subtle header/corner zoom readout that progressively layers `11 pt` spinner + `Preview` or
/// static muted `Preview only` without shifting existing controls.
struct DetailProgressiveDecodeReadout: View {
    enum Tone {
        case header
        case darkScrim
    }

    let photoID: PhotoIdentity
    let prefixText: String?
    var accessiblePrefixText: String? = nil
    let zoomText: String?
    let showsProgressiveState: Bool
    let phase: RawProgressiveDecodePhase
    let language: ResolvedAppLanguage
    var tone: Tone = .header
    var font: Font? = nil
    var leadingIcon: String? = nil
    var iconSize: CGFloat = 11
    var lineLimit: Int? = 1
    var minimumScaleFactor: CGFloat = 0.78
    let identifier: String
    var reportHeaderFrame: Bool = false

    @Environment(\.cloveTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settledPhotoID: PhotoIdentity?

    private let spinnerPointSize: CGFloat = 11
    private let systemSmallSpinnerSize: CGFloat = 20

    private var presentation: DetailZoomReadoutPresentation {
        DetailZoomReadoutPresentation(
            prefixText: prefixText,
            accessiblePrefixText: accessiblePrefixText,
            zoomText: zoomText,
            showsProgressiveState: showsProgressiveState,
            phase: phase,
            language: language
        )
    }

    private var primaryColor: Color {
        switch tone {
        case .header:
            theme.tokens.secondaryText.color
        case .darkScrim:
            Color.white.opacity(0.86)
        }
    }

    private var mutedColor: Color {
        switch tone {
        case .header:
            theme.tokens.secondaryText.color.opacity(0.68)
        case .darkScrim:
            Color.white.opacity(0.68)
        }
    }

    private var shouldAnimatePhase: Bool {
        CloveMotion.shouldAnimateMarkChange(settledPhotoID: settledPhotoID, currentPhotoID: photoID)
    }

    private var phaseAnimation: Animation? {
        guard !reduceMotion, shouldAnimatePhase else { return nil }
        guard showsProgressiveState, presentation.visualPhase != .previewOnly else { return nil }
        return CloveMotion.focusArrival(reduceMotion: false)
    }

    var body: some View {
        let model = presentation
        let styled = readoutContent(model)
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
            .truncationMode(.tail)
            .animation(phaseAnimation, value: model.visualPhase)
            .onAppear { settledPhotoID = photoID }
            .onChange(of: photoID) { _, newValue in
                settledPhotoID = newValue
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(model.accessibilityLabel)
            .modifier(OptionalAccessibilityValue(value: model.accessibilityValue))
            .accessibilityIdentifier(identifier)

        if reportHeaderFrame {
            styled.reportHeaderControlFrame(identifier)
        } else {
            styled
        }
    }

    @ViewBuilder
    private func readoutContent(_ model: DetailZoomReadoutPresentation) -> some View {
        if let font {
            baseHStack(model)
                .font(font.monospacedDigit())
        } else {
            baseHStack(model)
                .monospacedDigit()
        }
    }

    private func baseHStack(_ model: DetailZoomReadoutPresentation) -> some View {
        HStack(alignment: .center, spacing: 0) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(primaryColor)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
            }

            if model.showsSpinner {
                if let prefix = model.visiblePrefix {
                    Text("\(prefix) · ")
                        .foregroundStyle(primaryColor)
                }

                ProgressView()
                    .controlSize(.small)
                    .tint(primaryColor)
                    .scaleEffect(spinnerPointSize / systemSmallSpinnerSize)
                    .frame(width: spinnerPointSize, height: spinnerPointSize)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
                    .transition(.opacity)

                zoomAndStatusText(model)
                    .transition(.opacity)
            } else {
                combinedStaticText(model)
            }
        }
    }

    private func zoomAndStatusText(_ model: DetailZoomReadoutPresentation) -> Text {
        if let zoom = model.primaryZoomText, let status = model.trailingStatusText {
            let formatted = AppLocalization.format("%@ · %@", language: language, zoom, status)
            if let range = formatted.range(of: zoom),
                range.lowerBound == formatted.startIndex
            {
                let rest = String(formatted[range.upperBound...])
                return Text(zoom).foregroundColor(primaryColor)
                    + Text(rest).foregroundColor(mutedColor)
            }
            return Text(formatted).foregroundColor(mutedColor)
        }
        if let zoom = model.primaryZoomText {
            return Text(zoom).foregroundColor(primaryColor)
        }
        if let status = model.trailingStatusText {
            return Text(status).foregroundColor(mutedColor)
        }
        return Text("").foregroundColor(primaryColor)
    }

    private func combinedStaticText(_ model: DetailZoomReadoutPresentation) -> Text {
        switch (model.visiblePrefix, model.primaryZoomText, model.trailingStatusText) {
        case (.some(let prefix), .some(let zoom), .none):
            return Text("\(prefix) · \(zoom)").foregroundColor(primaryColor)
        case (.none, .some(let zoom), .none):
            return Text(zoom).foregroundColor(primaryColor)
        case (.some(let prefix), .none, .none):
            return Text(prefix).foregroundColor(primaryColor)
        case (.some(let prefix), .none, .some(let status)):
            return Text("\(prefix) · ").foregroundColor(primaryColor)
                + Text(status).foregroundColor(mutedColor)
        case (.none, .none, .some(let status)):
            return Text(status).foregroundColor(mutedColor)
        default:
            return zoomAndStatusText(model)
        }
    }
}

private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?

    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}
