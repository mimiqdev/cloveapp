import Foundation
import Testing

@testable import CameraFocusMetadata

@Suite("Hasselblad Batch 2 AF metadata")
struct HasselbladFocusMetadataTests {
    private let reader = FocusMetadataReader()

    private func buildHasselbladTIFF(
        order: TIFFByteOrder = .littleEndian,
        model: String = "X2D 100C",
        orientation: UInt16 = 1,
        words: [UInt16] = [1, 5001, 5001, 464, 672, 0, 0],
        inactiveFlag: UInt16? = 0,
        placeOutsideMakerNote: Bool = false,
        duplicateFocusTag: Bool = false
    ) -> [UInt8] {
        var entries: [(tag: UInt16, type: UInt16, count: UInt32, value: [UInt8])] = []
        let focusBytes = VendorContainerBuilder.encodeWords(words, order: order)
        entries.append((0x0047, 3, UInt32(words.count), focusBytes))
        if duplicateFocusTag {
            entries.append((0x0047, 3, UInt32(words.count), focusBytes))
        }
        if let inactiveFlag {
            let flagBytes = VendorContainerBuilder.encodeWords([inactiveFlag], order: order)
            entries.append((0x004A, 3, 1, flagBytes))
        }
        let debugBytes = Array("AF_DEBUG_INFO: focus point".utf8) + [0]
        entries.append((0x004B, 2, UInt32(debugBytes.count), debugBytes))

        return VendorContainerBuilder.enclosingTIFFMakerNoteTIFF(
            order: order,
            make: "Hasselblad",
            model: model,
            orientation: orientation,
            imageExtent: nil,
            makerNoteHeader: [],
            makerNoteEntries: entries,
            placeMakerNoteValuesOutsideMakerNoteRange: placeOutsideMakerNote
        )
    }

    @Test(
        "Decodes LE 3FR and BE FFF containers including out-of-line values in enclosing outer TIFF")
    func littleEndianAndBigEndianWithExternalValues() throws {
        let quadrants: [(cx: UInt16, cy: UInt16, w: UInt16, h: UInt16)] = [
            (2500, 2500, 464, 672),
            (7500, 2500, 464, 672),
            (2500, 7500, 928, 1344),
            (4992, 3529, 928, 1344),
        ]

        for order in [TIFFByteOrder.littleEndian, .bigEndian] {
            for quadrant in quadrants {
                let tiff = buildHasselbladTIFF(
                    order: order,
                    model: order == .bigEndian ? "Hasselblad X2D 100C" : "X1D II 50C",
                    words: [1, quadrant.cx, quadrant.cy, quadrant.w, quadrant.h, 0, 0],
                    placeOutsideMakerNote: true
                )
                let report = try reader.read(data: Data(tiff))
                #expect(report.status == .verifiedVendorFocusMetadata)
                #expect(report.camera?.vendor == .hasselblad)
                #expect(report.container.byteOrder == order)
                #expect(report.container.makerNoteFlavor == .hasselblad)
                #expect(report.focus?.source == .hasselbladMakerNote)
                guard case .region(let stored)? = report.focus?.geometry else {
                    Issue.record("Expected Hasselblad 10000x10000 region")
                    continue
                }
                #expect(stored.extent == PixelExtent(width: 10_000, height: 10_000))
                #expect(
                    stored.center == ContinuousPoint(x: Double(quadrant.cx), y: Double(quadrant.cy))
                )
                #expect(
                    stored.size
                        == ContinuousSize(width: Double(quadrant.w), height: Double(quadrant.h)))
            }
        }
    }

    @Test("All 8 EXIF orientations transform 10000x10000 stored Hasselblad coordinates accurately")
    func allEightOrientations() throws {
        let tiffCoords = (cx: UInt16(6124), cy: UInt16(5042), w: UInt16(928), h: UInt16(1344))
        let expectations: [(orientation: UInt16, center: ContinuousPoint, size: ContinuousSize)] = [
            (1, ContinuousPoint(x: 6124, y: 5042), ContinuousSize(width: 928, height: 1344)),
            (2, ContinuousPoint(x: 3876, y: 5042), ContinuousSize(width: 928, height: 1344)),
            (3, ContinuousPoint(x: 3876, y: 4958), ContinuousSize(width: 928, height: 1344)),
            (4, ContinuousPoint(x: 6124, y: 4958), ContinuousSize(width: 928, height: 1344)),
            (5, ContinuousPoint(x: 5042, y: 6124), ContinuousSize(width: 1344, height: 928)),
            (6, ContinuousPoint(x: 4958, y: 6124), ContinuousSize(width: 1344, height: 928)),
            (7, ContinuousPoint(x: 4958, y: 3876), ContinuousSize(width: 1344, height: 928)),
            (8, ContinuousPoint(x: 5042, y: 3876), ContinuousSize(width: 1344, height: 928)),
        ]

        for item in expectations {
            let tiff = buildHasselbladTIFF(
                order: .littleEndian,
                model: "X1D II 50C",
                orientation: item.orientation,
                words: [1, tiffCoords.cx, tiffCoords.cy, tiffCoords.w, tiffCoords.h, 0, 0]
            )
            let report = try reader.read(data: Data(tiff))
            #expect(report.status == .verifiedVendorFocusMetadata)
            guard case .region(let display)? = report.displayGeometry else {
                Issue.record(
                    "Expected display geometry for Hasselblad orientation \(item.orientation)")
                continue
            }
            #expect(display.extent == PixelExtent(width: 10_000, height: 10_000))
            #expect(display.center == item.center)
            #expect(display.size == item.size)
        }
    }

    @Test(
        "Handles Flexbody/inactive MF states, invalid dimensions, unverified counts, and Sony Lunar disambiguation"
    )
    func mfStatesAndEdgeCases() throws {
        // Inactive activeFlag == 0 -> noRegionRecorded
        let inactiveReport = try reader.read(
            data: Data(buildHasselbladTIFF(words: [0, 5000, 5000, 464, 672, 0, 0]))
        )
        #expect(inactiveReport.status == .verifiedVendorFocusMetadata)
        #expect(
            inactiveReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .hasselblad)))

        // CFV 100C Flexbody (1, 0, 0, 0, 0, 0, 0) with 0x004a == 1 -> noRegionRecorded
        let flexReport = try reader.read(
            data: Data(
                buildHasselbladTIFF(
                    model: "CFV 100C/Electronic Shutter", words: [1, 0, 0, 0, 0, 0, 0],
                    inactiveFlag: 1))
        )
        #expect(flexReport.status == .verifiedVendorFocusMetadata)
        #expect(flexReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .hasselblad)))

        // Zero size with nonzero center -> zeroRegionExtent
        let zeroSizeReport = try reader.read(
            data: Data(buildHasselbladTIFF(words: [1, 5000, 5000, 0, 672, 0, 0]))
        )
        #expect(zeroSizeReport.focus?.geometry == .unavailable(.zeroRegionExtent))

        // Out-of-range center -> centerOutsideReference
        let oobCenterReport = try reader.read(
            data: Data(buildHasselbladTIFF(words: [1, 10_500, 5000, 464, 672, 0, 0]))
        )
        #expect(oobCenterReport.focus?.geometry == .unavailable(.centerOutsideReference))

        // Extended > 7 words -> rawVendorObservation + vendorSemanticsUnverified
        let extendedReport = try reader.read(
            data: Data(buildHasselbladTIFF(words: [1, 5000, 5000, 464, 672, 0, 0, 1, 2]))
        )
        #expect(extendedReport.status == .rawVendorObservation)
        #expect(
            extendedReport.focus?.geometry
                == .unavailable(.vendorSemanticsUnverified(vendor: .hasselblad)))

        // Sony-rebadged Hasselblad Lunar continues using Sony unprefixed MakerNote
        let sonyLocBytes = VendorContainerBuilder.encodeWords(
            [6000, 4000, 1500, 1000], order: .littleEndian)
        var sonyFocusMode: [UInt8] = []
        TestSupport.appendUInt16(3, to: &sonyFocusMode, order: .littleEndian)
        let lunarTIFF = VendorContainerBuilder.enclosingTIFFMakerNoteTIFF(
            order: .littleEndian,
            make: "HASSELBLAD",
            model: "Lunar",
            makerNoteEntries: [
                (0x201B, 3, 1, sonyFocusMode),
                (0x2027, 3, 4, sonyLocBytes),
            ]
        )
        let lunarReport = try reader.read(data: Data(lunarTIFF))
        #expect(lunarReport.container.makerNoteFlavor == .sonyUnprefixed)
        #expect(lunarReport.focus?.source == .sonyLocationRecord)
        #expect(lunarReport.focus?.sony != nil)
        #expect(lunarReport.status == .verifiedSonyFocusMetadata)
    }

    @Test("Rejects duplicate 0x0047 and short/truncated MakerNote payloads")
    func malformedHasselblad() throws {
        let dupReport = try reader.read(
            data: Data(buildHasselbladTIFF(duplicateFocusTag: true))
        )
        #expect(dupReport.status == .malformed)
        #expect(dupReport.issues.contains { $0.kind == .duplicateTag })

        let shortReport = try reader.read(
            data: Data(buildHasselbladTIFF(words: [1, 5000, 5000]))
        )
        #expect(shortReport.status == .malformed)
        #expect(shortReport.issues.contains { $0.kind == .unexpectedFieldShape })

        var truncatedBuilder = TestTIFFBuilder()
        truncatedBuilder.make = "Hasselblad"
        truncatedBuilder.model = "X2D 100C"
        truncatedBuilder.makerNote = [0x01]
        let truncReport = try reader.read(data: Data(truncatedBuilder.build()))
        #expect(truncReport.status == .malformed)
        #expect(truncReport.issues.contains { $0.kind == .malformedMakerNote })
    }
}
