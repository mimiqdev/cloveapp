/// The device sizes `design/handoff/components.md` measures a control at.
///
/// The mark capsule, stars, toast, banner and pill action have one size, measured on the iPhone
/// frames, so they take no size. The controls that appear on more than one device take it.
enum ControlSize {
    /// The iPhone sizes, measured on a 390 × 844 frame (components.md).
    case phone

    /// The iPad sizes, from the iPad frames (components.md).
    case pad

    /// The Duo dock sizes, from the Duo frames (components.md).
    case duo
}
