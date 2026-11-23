import Foundation
import Testing

@testable import CameraFocusMetadata

@Suite("Leica Batch 2 MakerNote observation")
struct LeicaFocusMetadataTests {
    private let reader = FocusMetadataReader()

    @Test(
        "Recognizes LEICA\\0 variants (M10-R, Q2, SL2, SL3) across DNG and JPEG without inventing coordinates"
    )
    func nativeLeicaVariants() throws {
        let variants: [(bytes: [UInt8], model: String, orient: UInt16)] = [
            (Array("LEICA\0\u{02}\0".utf8), "LEICA M10-R", 1),
            (Array("LEICA\0\u{09}\0".utf8), "LEICA Q2", 1),
            (Array("LEICA\0\u{09}\0".utf8), "LEICA SL2", 8),
            (Array("LEICA\0\u{0a}\0".utf8), "LEICA SL3", 6),
        ]

        for variant in variants {
            var sl3Vals: [UInt8] = []
            for word: UInt32 in [2582, 237, 1189, 202, 34, 0] {
                TestSupport.appendUInt32(word, to: &sl3Vals, order: .littleEndian)
            }
            let opaque = Array("##START##".utf8) + [UInt8](repeating: 0xAA, count: 64)
            let tiff = VendorContainerBuilder.enclosingTIFFMakerNoteTIFF(
                order: .littleEndian,
                make: "Leica Camera AG",
                model: variant.model,
                orientation: variant.orient,
                imageExtent: (6000, 4000),
                makerNoteHeader: variant.bytes,
                makerNoteEntries: [
                    (0x0304, 4, 1, [1, 0, 0, 0]),
                    (0x0442, 4, 6, sl3Vals),
                    (0x04FF, 7, UInt32(opaque.count), opaque),
                ]
            )

            for data in [
                Data(tiff), VendorContainerBuilder.jpeg(exifTIFF: tiff, sofExtent: (6000, 4000)),
            ] {
                let report = try reader.read(data: data)
                #expect(report.status == .rawVendorObservation)
                #expect(report.camera?.vendor == .leica)
                #expect(report.container.makerNoteFlavor == .leica)
                #expect(report.focus?.source == .leicaMakerNote)
                #expect(
                    report.focus?.geometry
                        == .unavailable(.vendorSemanticsUnverified(vendor: .leica)))
                #expect(report.displayGeometry == nil)
                #expect(report.uncertainties.contains(.vendorGeometryUnverified))
            }
        }
    }

    @Test("Handles Leica X2 (05 00) MakerNote-relative out-of-line offsets cleanly")
    func leicaX2RelativeOffsets() throws {
        let opaque = Array("##START##\u{05}\0".utf8) + [UInt8](repeating: 0x42, count: 32)
        let x2Vals = VendorContainerBuilder.encodeWords(
            [10, 20, 30, 40, 50, 60], order: .littleEndian)
        let tiff = VendorContainerBuilder.enclosingTIFFMakerNoteTIFF(
            order: .littleEndian,
            make: "LEICA",
            model: "LEICA X2",
            makerNoteHeader: Array("LEICA\0\u{05}\0".utf8),
            makerNoteEntries: [
                (0x0304, 1, 1, [0]),
                (0x0442, 3, 6, x2Vals),
                (0x04FF, 7, UInt32(opaque.count), opaque),
            ],
            useMakerNoteRelativeOffsets: true
        )
        let report = try reader.read(data: Data(tiff))
        #expect(report.status == .rawVendorObservation)
        #expect(report.camera?.vendor == .leica)
        #expect(report.container.makerNoteFlavor == .leica)
        #expect(report.issues.isEmpty)
        #expect(report.focus?.vendor?.records.contains { $0.tag == 0x04FF } == true)
    }

    @Test("Handles Panasonic-derived LEICA CAMERA AG D-Lux RW2 with unverified origin")
    func panasonicDerivedLeicaRW2() throws {
        var ratBytes: [UInt8] = []
        for value: UInt32 in [158, 256, 128, 256] {
            TestSupport.appendUInt32(value, to: &ratBytes, order: .littleEndian)
        }
        var modeBytes: [UInt8] = []
        TestSupport.appendUInt16(1, to: &modeBytes, order: .littleEndian)
        let tiff = VendorContainerBuilder.enclosingTIFFMakerNoteTIFF(
            order: .littleEndian,
            make: "LEICA",
            model: "D-Lux 7",
            makerNoteHeader: Array("LEICA CAMERA AG\0\0\0".utf8),
            makerNoteEntries: [
                (0x0007, 3, 1, modeBytes),
                (0x004D, 5, 2, ratBytes),
            ]
        )
        let rw2 = VendorContainerBuilder.rw2(exifTIFF: tiff)
        let report = try reader.read(data: rw2)
        #expect(report.status == .rawVendorObservation)
        #expect(report.container.kind == .panasonicRW2)
        #expect(report.container.makerNoteFlavor == .leicaPanasonicDerived)
        #expect(report.focus?.source == .leicaPanasonicAFPosition)
        #expect(report.focus?.geometry == .unavailable(.originConventionUnverified(vendor: .leica)))
        #expect(report.displayGeometry == nil)
    }

    @Test("Rejects truncated or malformed Leica MakerNotes safely")
    func malformedLeica() throws {
        var shortBuilder = TestTIFFBuilder()
        shortBuilder.make = "Leica Camera AG"
        shortBuilder.model = "LEICA Q3"
        shortBuilder.makerNote = Array("LEICA\0\u{0a}\0".utf8)
        let shortReport = try reader.read(data: Data(shortBuilder.build()))
        #expect(shortReport.status == .malformed)
        #expect(shortReport.issues.contains { $0.kind == .malformedMakerNote })

        var badCountBuilder = TestTIFFBuilder()
        badCountBuilder.make = "LEICA"
        badCountBuilder.model = "D-Lux 7"
        var badMN = Array("LEICA CAMERA AG\0\0\0".utf8)
        badMN.append(contentsOf: [0xFF, 0x0F])  // Huge count inside short MakerNote
        badCountBuilder.makerNote = badMN
        let badReport = try reader.read(data: Data(badCountBuilder.build()))
        #expect(badReport.status == .malformed)
    }
}
