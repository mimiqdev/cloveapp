import Foundation

/// Whether a render creates a `CIContext` or reuses one kept by the renderer.
public enum RAWContextStrategy: String, Sendable, CaseIterable {
    /// A new `CIContext` for this render: what the Clove detail pipeline does today.
    case fresh
    /// One `CIContext` created when the renderer was built and reused afterwards.
    case reused
}

/// The output size a RAW variant asks the decoder for.
///
/// There is deliberately no "render native, then downscale" case: that route is
/// what S2 measured for its 2000 px row, and this probe isolates decode-time
/// scaling instead.
public enum RAWDisplayScale: Sendable, Hashable {
    /// No `scaleFactor`; the decoder renders its native size.
    case native
    /// `CIRAWFilter.scaleFactor` set so the output's long edge is about this many pixels.
    case longEdge(Int)

    /// Long edge in pixels, or 0 when the render is native.
    public var requestedLongEdge: Int {
        switch self {
        case .native: return 0
        case .longEdge(let edge): return edge
        }
    }
}

/// One RAW render variant: how large, draft or not, and with which context.
public struct RAWDisplayVariant: Sendable, Hashable {
    /// What the variant is for, so reports can group native, screen and grid rows.
    public enum Role: String, Sendable, CaseIterable {
        case native, screen, grid
    }

    /// Stable report tag. A topic name, never a plan identifier.
    public let name: String
    public let scale: RAWDisplayScale
    public let draft: Bool
    public let context: RAWContextStrategy
    public let role: Role

    public init(
        name: String, scale: RAWDisplayScale, draft: Bool, context: RAWContextStrategy,
        role: Role
    ) {
        self.name = name
        self.scale = scale
        self.draft = draft
        self.context = context
        self.role = role
    }

    /// Long edge the variant asks for, or 0 for a native render.
    public var requestedLongEdge: Int { scale.requestedLongEdge }

    /// How the decoder was asked for the output size, for report tags and prose.
    public var scaleMethod: String {
        switch scale {
        case .native: return "nativeSize"
        case .longEdge: return "CIRAWFilter.scaleFactor"
        }
    }

    /// The five brief variants, with the grid and screen sizes resolved for this run.
    ///
    /// `screenLongEdge` comes from the Lab app because `CloveLabKit` stays UIKit-free.
    public static func standard(screenLongEdge: Int) -> [RAWDisplayVariant] {
        [
            RAWDisplayVariant(
                name: "raw-native-fresh-context", scale: .native, draft: false,
                context: .fresh, role: .native),
            RAWDisplayVariant(
                name: "raw-native-reused-context", scale: .native, draft: false,
                context: .reused, role: .native),
            RAWDisplayVariant(
                name: "raw-screen-scale", scale: .longEdge(screenLongEdge), draft: false,
                context: .reused, role: .screen),
            RAWDisplayVariant(
                name: "raw-screen-scale-draft", scale: .longEdge(screenLongEdge), draft: true,
                context: .reused, role: .screen),
            RAWDisplayVariant(
                name: "raw-grid-scale", scale: .longEdge(400), draft: false, context: .reused,
                role: .grid),
            RAWDisplayVariant(
                name: "raw-grid-scale-draft", scale: .longEdge(400), draft: true,
                context: .reused, role: .grid),
        ]
    }
}

/// One camera HEIF (HIF) render variant: the camera-preview mode's 100% source.
public struct CameraPreviewVariant: Sendable, Hashable {
    /// How the HEIF is decoded.
    public enum Kind: Sendable, Hashable {
        /// A full HEIF decode through `CGImageSourceCreateImageAtIndex`.
        case fullDecode
        /// A full decode that asks ImageIO for `kCGImageSourceSubsampleFactor`.
        case subsample(Int)
        /// A thumbnail decoded from the full image with `CreateThumbnailFromImageAlways`.
        case screenThumbnail(Int)
    }

    /// Stable report tag. A topic name, never a plan identifier.
    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// Full decode, subsample factor 2, and the screen long edge, in that order.
    public static func standard(screenLongEdge: Int) -> [CameraPreviewVariant] {
        [
            CameraPreviewVariant(name: "camera-full-decode", kind: .fullDecode),
            CameraPreviewVariant(name: "camera-subsample-2", kind: .subsample(2)),
            CameraPreviewVariant(
                name: "camera-screen-thumbnail", kind: .screenThumbnail(screenLongEdge)),
        ]
    }

    /// How the decode was asked for the output size, for report tags and prose.
    public var scaleMethod: String {
        switch kind {
        case .fullDecode: return "fullDecode"
        case .subsample: return "kCGImageSourceSubsampleFactor"
        case .screenThumbnail: return "kCGImageSourceCreateThumbnailFromImageAlways"
        }
    }

    /// Long edge the variant asks for, or 0 when it is a full decode.
    public var requestedLongEdge: Int {
        switch kind {
        case .fullDecode: return 0
        case .subsample: return 0
        case .screenThumbnail(let edge): return edge
        }
    }
}

/// Where a render sits in the run: a one-off startup render, the first measured
/// render of its variant, or a repeat.
public enum RAWDisplayPhase: String, Sendable, CaseIterable {
    /// One untimed render before the cold pass, reported on its own row. It absorbs
    /// the process's first Core Image and RAW setup so variant a's cold number is
    /// comparable with the others.
    case startup
    case cold, warm
}
