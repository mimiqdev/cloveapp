import Testing

@testable import CloveImaging

/// G1 "Grouping (C9/I3)": a boundary is compared with Vision prints when both photos have one,
/// with difference hashes when either side lacks Vision, and never with one of each. Thresholds
/// stay in C9, so these tests check only the raw distance and its kind.
@Suite(.serialized)
struct ImageFeatureDistanceTests {
    @Test func visionPrintDistanceIsTheEuclideanDistance() throws {
        let one = samplePrint(base: 1)
        let two = samplePrint(base: 2)
        let distance = try #require(one.distance(to: two))
        // Four elements each one apart: sqrt(4).
        #expect(abs(distance - 2) < 1e-6)
        #expect(one.distance(to: one) == 0)
    }

    @Test func bothPrintsAnswerVision() throws {
        let left = ImageFeatures(
            print: samplePrint(base: 1), differenceHash: DifferenceHash(bits: 0))
        let right = ImageFeatures(
            print: samplePrint(base: 2), differenceHash: DifferenceHash(bits: 0b1111))
        let distance = try #require(left.distance(to: right))
        #expect(distance.kind == .visionPrint)
        #expect(abs(distance.value - 2) < 1e-6)
    }

    @Test func oneMissingPrintFallsBackToTheHash() throws {
        let left = ImageFeatures(
            print: samplePrint(), differenceHash: DifferenceHash(bits: 0b0000))
        let right = ImageFeatures(
            differenceHash: DifferenceHash(bits: 0b1011),
            visionFailure: FeatureFailure(domain: "NSOSStatusErrorDomain", code: -1, message: "no"))
        let distance = try #require(left.distance(to: right))
        #expect(distance.kind == .differenceHash)
        #expect(distance.value == 3)
    }

    @Test func noUsableFeatureAnswersNothing() throws {
        let empty = ImageFeatures()
        #expect(empty.distance(to: empty) == nil)
        // One side has only a print and the other only a hash: neither kind pairs up, so
        // grouping must split rather than compare two different features.
        let printOnly = ImageFeatures(print: samplePrint())
        let hashOnly = ImageFeatures(differenceHash: DifferenceHash(bits: 1))
        #expect(printOnly.distance(to: hashOnly) == nil)
        #expect(hashOnly.distance(to: printOnly) == nil)
    }

    @Test func incomparablePrintsFallBackToTheHash() throws {
        // A new Vision revision never compares against an older print (G1 cache identity).
        let left = ImageFeatures(
            print: samplePrint(revision: 2, base: 1), differenceHash: DifferenceHash(bits: 0))
        let right = ImageFeatures(
            print: samplePrint(revision: 3, base: 1), differenceHash: DifferenceHash(bits: 0b111))
        #expect(left.print?.distance(to: try #require(right.print)) == nil)
        let distance = try #require(left.distance(to: right))
        #expect(distance.kind == .differenceHash)
        #expect(distance.value == 3)
        let withoutHashes = ImageFeatures(print: samplePrint(revision: 2))
        let newer = ImageFeatures(print: samplePrint(revision: 3))
        #expect(withoutHashes.distance(to: newer) == nil)
    }

    @Test func mismatchedPrintLengthsAreNotComparable() {
        let short = VisionFeaturePrint(revision: 2, elements: [1, 2])
        let long = VisionFeaturePrint(revision: 2, elements: [1, 2, 3])
        #expect(short.distance(to: long) == nil)
        #expect(VisionFeaturePrint(revision: 2, elements: []).distance(to: short) == nil)
    }

    @Test func hashDistanceCountsDifferingBits() {
        let left = DifferenceHash(bits: 0b1011)
        let right = DifferenceHash(bits: 0b0010)
        #expect(left.distance(to: right) == 2)
        #expect(left.distance(to: left) == 0)
        // 64 bits apart, the largest dHash distance.
        #expect(
            DifferenceHash(bits: 0).distance(to: DifferenceHash(bits: .max)) == 64)
    }

    @Test func kindsListWhatSucceeded() {
        #expect(
            ImageFeatures(print: samplePrint(), differenceHash: .init(bits: 0)).kinds == [
                .visionPrint, .differenceHash,
            ])
        #expect(ImageFeatures(differenceHash: .init(bits: 0)).kinds == [.differenceHash])
        #expect(ImageFeatures().kinds.isEmpty)
    }

    @Test func visionPrintReportsItsSize() {
        // G1 asks the feature timing to report the stored size: 768 floats at revision 2.
        let print = VisionFeaturePrint(
            revision: 2, elements: [Float](repeating: 0, count: 768))
        #expect(print.elementCount == 768)
        #expect(print.byteCount == 3072)
    }
}
