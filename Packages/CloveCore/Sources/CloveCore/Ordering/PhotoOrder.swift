/// How the grid orders its photos (PRD P0-03, G1 decision 3).
public enum PhotoOrder: Hashable, Sendable {
    /// The default: capture time with subseconds and file-time fallbacks on one timeline,
    /// ascending, with photos that have no usable time after every timed photo.
    case captureTime
    /// The option: relative folder path, then file name compared with
    /// `String.localizedStandardCompare`, so `IMG_9` sorts before `IMG_10`. The identity
    /// breaks the remaining ties.
    case fileName
}
