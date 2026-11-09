import Foundation

import CloveCore

/// The opened folder used by the ordering tests; identity only, never a path.
let orderingFolder = FolderIdentity(rawValue: "opened-folder")

/// Base instant for the ordering tests, so offsets and fractions stay readable.
let orderingBase = Date(timeIntervalSince1970: 1_700_000_000)

/// An instant `offset` seconds after the base, fractions included.
func seconds(_ offset: Double) -> Date { orderingBase.addingTimeInterval(offset) }

/// A known capture time, with an explicit UTC offset by default.
func capture(_ instant: Date, offset: Bool = true) -> PhotoTimeState {
    .known(PhotoTime(captureTime: instant, hasUTCOffset: offset))
}

/// A known file creation time, used only as a sorting fallback.
func fileCreation(_ instant: Date) -> PhotoTimeState {
    .known(PhotoTime(fileCreation: instant))
}

/// A known file modification time, used only as a sorting fallback.
func fileModification(_ instant: Date) -> PhotoTimeState {
    .known(PhotoTime(fileModification: instant))
}

/// Builds one grid photo with an explicit time state; identity folds `stem` to lower case.
func photo(
    _ stem: String,
    time: PhotoTimeState,
    path: String = "DCIM/100CAM",
    folder: FolderIdentity = orderingFolder,
    fileName: String? = nil,
    marks: PhotoMarks = PhotoMarks()
) -> GridPhoto {
    GridPhoto(
        id: PhotoIdentity(folderID: folder, relativeFolderPath: path, stem: stem),
        fileName: fileName ?? "\(stem).ARW",
        time: time,
        marks: marks)
}

/// Builds marks from the tests' 0–5 stars and a clear label by default.
func marks(stars: Int = 0, label: ColourLabel = .clear, rejected: Bool = false) -> PhotoMarks {
    guard let rating = Rating(rawValue: stars) else {
        preconditionFailure("ordering tests only use 0–5 stars")
    }
    return PhotoMarks(rating: rating, label: label, isRejected: rejected)
}

/// A reproducible random source, so a failing permutation replays from its seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Milliseconds from a measured duration, in the units the timing report uses.
func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
}
