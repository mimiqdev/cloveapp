import Foundation
import Testing

@testable import CameraFocusMetadata

@Suite("Ricoh Batch 2 AF metadata")
struct RicohFocusMetadataTests {
    private let reader = FocusMetadataReader()

    @Test(
        "Decodes DNG 0xc634 and JPEG MakerNote 0x040c with identical 720x480 geometry across quadrants"
    )
    func dngAndJpegDecodeFourQuadrants() throws {
        let quadrants: [(cx: UInt16, cy: UInt16, w: UInt16, h: UInt16)] = [
            (180, 120, 64, 52),
            (540, 120, 64, 52),
            (180, 360, 112, 72),
            (540, 360, 112, 72),
        ]

        for quadrant in quadrants {
            let block = VendorContainerBuilder.ricohStructuredBlock(
                formatVersion: 8193,
                slots: [
                    (
                        refW: 720,
                        refH: 480,
                        cx: quadrant.cx,
                        cy: quadrant.cy,
                        w: quadrant.w,
                        h: quadrant.h,
                        flags: 15
                    )
                ]
            )

            let dng = VendorContainerBuilder.ricohDNGWithPrivateData(
                model: "RICOH GR IIIx",
                orientation: 1,
                imageExtent: (6000, 4000),
                privateData: block
            )
            let dngReport = try reader.read(data: Data(dng))
            #expect(dngReport.status == .verifiedVendorFocusMetadata)
            #expect(dngReport.camera?.vendor == .ricoh)
            #expect(dngReport.container.makerNoteFlavor == .ricohVendorPayload)
            #expect(dngReport.focus?.source == .ricohPrivateData)
            guard case .region(let dngStored)? = dngReport.focus?.geometry else {
                Issue.record("Expected Ricoh DNG region")
                continue
            }
            #expect(dngStored.extent == PixelExtent(width: 720, height: 480))
            #expect(
                dngStored.center == ContinuousPoint(x: Double(quadrant.cx), y: Double(quadrant.cy)))
            #expect(
                dngStored.size
                    == ContinuousSize(width: Double(quadrant.w), height: Double(quadrant.h)))

            var tiffBuilder = TestTIFFBuilder()
            tiffBuilder.make = "RICOH IMAGING COMPANY, LTD."
            tiffBuilder.model = "RICOH GR IV"
            tiffBuilder.orientation = 1
            tiffBuilder.imageExtent = (6192, 4128)
            tiffBuilder.makerNote = block
            let jpeg = VendorContainerBuilder.jpeg(
                exifTIFF: tiffBuilder.build(),
                sofExtent: (width: 6192, height: 4128)
            )
            let jpegReport = try reader.read(data: jpeg)
            #expect(jpegReport.status == .verifiedVendorFocusMetadata)
            #expect(jpegReport.camera?.vendor == .ricoh)
            #expect(jpegReport.container.makerNoteFlavor == .ricoh)
            #expect(jpegReport.focus?.source == .ricohMakerNote)
            #expect(jpegReport.focus?.geometry == dngReport.focus?.geometry)
            #expect(jpegReport.displayGeometry == dngReport.displayGeometry)
        }
    }

    @Test(
        "Multi-box union includes flags 15 and 7 while ignoring evaluated background cells (flags 3)"
    )
    func multiBoxUnionFiltersFlags() throws {
        let block = VendorContainerBuilder.ricohStructuredBlock(
            formatVersion: 8194,
            slots: [
                (refW: 720, refH: 480, cx: 360, cy: 384, w: 112, h: 72, flags: 15),
                (refW: 720, refH: 480, cx: 136, cy: 384, w: 112, h: 72, flags: 7),
                // Evaluated grid cell NOT in focus (flags == 3) at top-right must not pull the union.
                (refW: 720, refH: 480, cx: 650, cy: 50, w: 112, h: 72, flags: 3),
            ]
        )
        let dng = VendorContainerBuilder.ricohDNGWithPrivateData(privateData: block)
        let report = try reader.read(data: Data(dng))
        #expect(report.status == .verifiedVendorFocusMetadata)
        guard case .region(let region)? = report.focus?.geometry else {
            Issue.record("Expected multi-box union region")
            return
        }
        // Left = 136 - 56 = 80, Right = 360 + 56 = 416 -> cx = 248, w = 336; cy = 384, h = 72.
        #expect(region.center == ContinuousPoint(x: 248, y: 384))
        #expect(region.size == ContinuousSize(width: 336, height: 72))
    }

    @Test("All 8 EXIF orientations transform stored 720x480 Ricoh coordinates cleanly")
    func allEightOrientations() throws {
        let block = VendorContainerBuilder.ricohStructuredBlock(
            slots: [(refW: 720, refH: 480, cx: 200, cy: 100, w: 80, h: 60, flags: 15)]
        )
        let landscape = try #require(PixelExtent(width: 720, height: 480))
        let portrait = try #require(PixelExtent(width: 480, height: 720))
        let expectations:
            [(
                orientation: UInt16, extent: PixelExtent, center: ContinuousPoint,
                size: ContinuousSize
            )] = [
                (
                    1, landscape, ContinuousPoint(x: 200, y: 100),
                    ContinuousSize(width: 80, height: 60)
                ),
                (
                    2, landscape, ContinuousPoint(x: 520, y: 100),
                    ContinuousSize(width: 80, height: 60)
                ),
                (
                    3, landscape, ContinuousPoint(x: 520, y: 380),
                    ContinuousSize(width: 80, height: 60)
                ),
                (
                    4, landscape, ContinuousPoint(x: 200, y: 380),
                    ContinuousSize(width: 80, height: 60)
                ),
                (
                    5, portrait, ContinuousPoint(x: 100, y: 200),
                    ContinuousSize(width: 60, height: 80)
                ),
                (
                    6, portrait, ContinuousPoint(x: 380, y: 200),
                    ContinuousSize(width: 60, height: 80)
                ),
                (
                    7, portrait, ContinuousPoint(x: 380, y: 520),
                    ContinuousSize(width: 60, height: 80)
                ),
                (
                    8, portrait, ContinuousPoint(x: 100, y: 520),
                    ContinuousSize(width: 60, height: 80)
                ),
            ]

        for item in expectations {
            var builder = TestTIFFBuilder()
            builder.make = "RICOH IMAGING COMPANY, LTD."
            builder.model = "RICOH GR III"
            builder.orientation = item.orientation
            builder.imageExtent = (6000, 4000)
            builder.makerNote = block
            let jpeg = VendorContainerBuilder.jpeg(
                exifTIFF: builder.build(),
                sofExtent: (width: 6000, height: 4000)
            )
            let report = try reader.read(data: jpeg)
            #expect(report.status == .verifiedVendorFocusMetadata)
            guard case .region(let display)? = report.displayGeometry else {
                Issue.record("Expected display geometry for orientation \(item.orientation)")
                continue
            }
            #expect(display.extent == item.extent)
            #expect(display.center == item.center)
            #expect(display.size == item.size)
        }
    }

    @Test(
        "Portrait-transposed pixel buffer with landscape 0x040c triggers orientationConflict while square crop succeeds"
    )
    func transposedPixelBufferGuardAndSquareCrop() throws {
        let block = VendorContainerBuilder.ricohStructuredBlock(
            slots: [(refW: 720, refH: 480, cx: 360, cy: 240, w: 64, h: 52, flags: 15)]
        )

        var transposedBuilder = TestTIFFBuilder()
        transposedBuilder.make = "RICOH IMAGING COMPANY, LTD."
        transposedBuilder.model = "RICOH GR IIIx"
        transposedBuilder.orientation = 1
        transposedBuilder.imageExtent = (4000, 6000)
        transposedBuilder.makerNote = block
        let transposedJPEG = VendorContainerBuilder.jpeg(
            exifTIFF: transposedBuilder.build(),
            sofExtent: (width: 4000, height: 6000)
        )
        let conflictReport = try reader.read(data: transposedJPEG)
        #expect(conflictReport.focus?.geometry == .unavailable(.orientationConflict))
        #expect(conflictReport.displayGeometry == nil)
        #expect(conflictReport.issues.contains { $0.kind == .referenceExtentMismatch })

        // Square 1:1 crop mode (4000x4000) does not falsely trigger orientationConflict.
        var squareBuilder = TestTIFFBuilder()
        squareBuilder.make = "RICOH IMAGING COMPANY, LTD."
        squareBuilder.model = "RICOH GR III"
        squareBuilder.orientation = 1
        squareBuilder.imageExtent = (4000, 4000)
        squareBuilder.makerNote = block
        let squareReport = try reader.read(data: Data(squareBuilder.build()))
        #expect(squareReport.status == .verifiedVendorFocusMetadata)
        #expect(squareReport.displayGeometry != nil)
    }

    @Test("MF / Snap state (255), empty active set, legacy GR II, and Pentax disambiguation")
    func mfEmptyLegacyAndPentaxDisambiguation() throws {
        let mfBlock = VendorContainerBuilder.ricohStructuredBlock(
            afState: 255,
            slots: [],
            focusSetting: 3
        )
        let mfReport = try reader.read(
            data: Data(VendorContainerBuilder.ricohDNGWithPrivateData(privateData: mfBlock))
        )
        #expect(mfReport.status == .verifiedVendorFocusMetadata)
        #expect(mfReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .ricoh)))

        let emptyActiveBlock = VendorContainerBuilder.ricohStructuredBlock(
            afState: 2,
            slots: [(refW: 720, refH: 480, cx: 360, cy: 240, w: 64, h: 52, flags: 3)]
        )
        let emptyReport = try reader.read(
            data: Data(
                VendorContainerBuilder.ricohDNGWithPrivateData(privateData: emptyActiveBlock))
        )
        #expect(emptyReport.status == .verifiedVendorFocusMetadata)
        #expect(emptyReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .ricoh)))

        // Unknown afState -> unverified raw observation
        let unknownStateBlock = VendorContainerBuilder.ricohStructuredBlock(
            afState: 9,
            slots: [(refW: 720, refH: 480, cx: 360, cy: 240, w: 64, h: 52, flags: 15)]
        )
        let unknownStateReport = try reader.read(
            data: Data(
                VendorContainerBuilder.ricohDNGWithPrivateData(privateData: unknownStateBlock))
        )
        #expect(unknownStateReport.status == .rawVendorObservation)
        #expect(
            unknownStateReport.focus?.geometry
                == .unavailable(.vendorSemanticsUnverified(vendor: .ricoh)))

        // Legacy GR II ("Ricoh\0\0\0" MakerNote)
        var modeVal: [UInt8] = []
        TestSupport.appendUInt16(2, to: &modeVal, order: .bigEndian)
        let legacyTIFF = VendorContainerBuilder.enclosingTIFFMakerNoteTIFF(
            order: .bigEndian,
            make: "RICOH IMAGING COMPANY, LTD.",
            model: "GR II",
            makerNoteHeader: Array("Ricoh\0\0\0".utf8),
            makerNoteEntries: [(0x1001, 3, 1, modeVal)]
        )
        let legacyReport = try reader.read(data: Data(legacyTIFF))
        #expect(legacyReport.status == .rawVendorObservation)
        #expect(legacyReport.camera?.vendor == .ricoh)
        #expect(legacyReport.container.makerNoteFlavor == .ricohLegacy)
        #expect(
            legacyReport.focus?.geometry == .unavailable(.vendorSemanticsUnverified(vendor: .ricoh))
        )

        // Pentax camera under "RICOH IMAGING COMPANY, LTD." Make remains .pentax
        var pentaxPayload = Array("PENTAX \0".utf8)
        pentaxPayload.append(contentsOf: [0x4D, 0x4D])  // MM
        pentaxPayload.append(contentsOf: [0x00, 0x01])  // count = 1
        pentaxPayload.append(contentsOf: [
            0x00, 0x0E, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        ])
        pentaxPayload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        let pentaxDNG = VendorContainerBuilder.ricohDNGWithPrivateData(
            make: "RICOH IMAGING COMPANY, LTD.",
            model: "PENTAX K-3 Mark III",
            privateData: pentaxPayload
        )
        let pentaxReport = try reader.read(data: Data(pentaxDNG))
        #expect(pentaxReport.camera?.vendor == .pentax)
        #expect(pentaxReport.container.makerNoteFlavor == .pentaxVendorPayload)
    }

    @Test("Rejects malformed, truncated, overflowed, and duplicate Ricoh 0x040c payloads")
    func malformedAndLimits() throws {
        // Declared maxBoxes = 65535 exceeding actual payload -> unexpectedFieldShape & malformed
        let overflowBlock = VendorContainerBuilder.ricohStructuredBlock(
            declaredMaxBoxes: UInt16.max,
            actualSlotCount: 1,
            slots: [(refW: 720, refH: 480, cx: 360, cy: 240, w: 64, h: 52, flags: 15)]
        )
        let overflowReport = try reader.read(
            data: Data(VendorContainerBuilder.ricohDNGWithPrivateData(privateData: overflowBlock))
        )
        #expect(overflowReport.status == .malformed)
        #expect(overflowReport.issues.contains { $0.kind == .unexpectedFieldShape })

        // Odd byte length in 0x040c
        let oddBlock = VendorContainerBuilder.ricohStructuredBlock(
            slots: [],
            overrideAFBytes: [UInt8](repeating: 0, count: 15)
        )
        let oddReport = try reader.read(
            data: Data(VendorContainerBuilder.ricohDNGWithPrivateData(privateData: oddBlock))
        )
        #expect(oddReport.status == .malformed)
        #expect(oddReport.issues.contains { $0.kind == .unexpectedFieldShape })

        // Duplicate 0x040c tag
        let dupBlock = VendorContainerBuilder.ricohStructuredBlock(
            slots: [(refW: 720, refH: 480, cx: 360, cy: 240, w: 64, h: 52, flags: 15)],
            duplicateAFInfo: true
        )
        let dupReport = try reader.read(
            data: Data(VendorContainerBuilder.ricohDNGWithPrivateData(privateData: dupBlock))
        )
        #expect(dupReport.status == .malformed)
        #expect(dupReport.issues.contains { $0.kind == .duplicateTag })

        // Truncated RICOH\0II header
        let shortPayload = Array("RICOH\0II\u{01}".utf8)
        let truncReport = try reader.read(
            data: Data(VendorContainerBuilder.ricohDNGWithPrivateData(privateData: shortPayload))
        )
        #expect(truncReport.status == .malformed)
        #expect(truncReport.issues.contains { $0.kind == .truncatedData })
    }
}
