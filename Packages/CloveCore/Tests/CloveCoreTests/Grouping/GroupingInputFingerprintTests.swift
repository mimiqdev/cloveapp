import Foundation
import Testing

@testable import CloveCore

/// PRD Similar groups rules: the cache key includes a digest of the eligible inputs, so these
/// tests pin what it covers and what it deliberately ignores.
@Test func theFingerprintIgnoresInputOrder() {
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]

    #expect(
        GroupingInputFingerprint.digest(of: photos)
            == GroupingInputFingerprint.digest(of: Array(photos.reversed())))
}

@Test func theFingerprintIgnoresIneligiblePhotos() {
    let eligible = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    let ineligible = [
        eligible[0],
        eligible[1],
        groupingPhoto(
            "fallback", at: 0.1,
            time: .known(PhotoTime(fileCreation: groupingSeconds(0.1)))),
        groupingPhoto("pending", at: 0.3, time: .pending),
        groupingPhoto("unknown-model", at: 0.4, model: nil),
    ]

    #expect(
        GroupingInputFingerprint.digest(of: eligible)
            == GroupingInputFingerprint.digest(of: ineligible))
}

@Test func theFingerprintChangesWithEveryGroupingInput() {
    let a = groupingPhoto("a", at: 0)
    let b = groupingPhoto("b", at: 0.2)
    let base = GroupingInputFingerprint.digest(of: [a, b])

    let variants = [
        [a, groupingPhoto("b", at: 0.21)],
        [a, groupingPhoto("b", at: 0.2, model: "Canon EOS R6")],
        [a, groupingPhoto("b", at: 0.2, serial: "SERIAL-1")],
        [a, groupingPhoto("b", at: 0.2, fileName: "OTHER.ARW")],
        [a, groupingPhoto("b", at: 0.2, path: "DCIM/101CAM")],
        [a],
        [groupingPhoto("b", at: 0.2)],
        [],
    ]
    for variant in variants {
        #expect(GroupingInputFingerprint.digest(of: variant) != base)
    }
}

/// The instant enters the digest by its full-precision bit pattern, so a microsecond change
/// that a rounded date would hide still invalidates a cached result.
@Test func theFingerprintCatchesASubsecondChange() {
    let a = groupingPhoto("a", at: 0)
    let slow = GroupingInputFingerprint.digest(
        of: [a, groupingPhoto("b", at: 0.2)])
    let fast = GroupingInputFingerprint.digest(
        of: [a, groupingPhoto("b", at: 0.200001)])

    #expect(slow != fast)
}
