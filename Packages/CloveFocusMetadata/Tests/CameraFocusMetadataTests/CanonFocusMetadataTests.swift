import Foundation
import Testing

@testable import CameraFocusMetadata

@Suite("Canon Batch 1 AF metadata")
struct CanonFocusMetadataTests {
    private let reader = FocusMetadataReader()

    @Test("CR3 parses CMT1, CMT2, and CMT3 and converts center-relative +Y-up coordinates")
    func cr3CMT3DecodesFourQuadrants() throws {
        // AFImage 6000x4000 -> center is (3000, 2000).
        // Point 0: raw (+600, +400) -> top-left stored (3600, 1600) -> normalized (0.60, 0.40)
        // Point 1: raw (-1200, -500) -> top-left stored (1800, 2500) -> normalized (0.30, 0.625)
        let points: [VendorContainerBuilder.CanonPoint] = [
            .init(width: 240, height: 160, x: 600, y: 400),
            .init(width: 200, height: 200, x: -1200, y: -500),
        ]

        // Quadrant 1 (+X, +Y up -> upper right in top-left image coordinates)
        let upperRightWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 2,
            validAFPoints: 2,
            afImageExtent: (6000, 4000),
            points: points,
            inFocusIndices: [0]
        )
        let upperRightReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(
                model: "Canon EOS R5",
                software: "Firmware 2.0",
                orientation: 1,
                imageExtent: (6000, 4000),
                afWords: upperRightWords
            )
        )
        #expect(upperRightReport.status == .verifiedVendorFocusMetadata)
        #expect(upperRightReport.camera?.vendor == .canon)
        #expect(upperRightReport.camera?.model == "Canon EOS R5")
        #expect(upperRightReport.camera?.recordedSoftware == "Firmware 2.0")
        #expect(upperRightReport.imageExtent == PixelExtent(width: 6000, height: 4000))
        #expect(upperRightReport.focus?.source == .canonCR3AFInformation)
        guard case .region(let stored1)? = upperRightReport.focus?.geometry else {
            Issue.record("Expected region geometry")
            return
        }
        #expect(stored1.center == ContinuousPoint(x: 3600, y: 1600))
        #expect(stored1.size == ContinuousSize(width: 240, height: 160))
        #expect(upperRightReport.displayGeometry?.asRegion == stored1.asDisplay(from: stored1))

        // Quadrant 3 (-X, -Y -> lower left in top-left image coordinates)
        let lowerLeftWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 2,
            validAFPoints: 2,
            afImageExtent: (6000, 4000),
            points: points,
            inFocusIndices: [1]
        )
        let lowerLeftReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(
                afWords: lowerLeftWords
            )
        )
        guard case .region(let stored2)? = lowerLeftReport.focus?.geometry else {
            Issue.record("Expected region geometry")
            return
        }
        #expect(stored2.center == ContinuousPoint(x: 1800, y: 2500))
        #expect(stored2.size == ContinuousSize(width: 200, height: 200))
    }

    @Test("Multi-point union spans multiple bitmask words (>16 points) and combines bounding box")
    func multiPointUnionAcrossMaskWords() throws {
        var points = Array(
            repeating: VendorContainerBuilder.CanonPoint(width: 100, height: 100, x: 0, y: 0),
            count: 20
        )
        // Point 2: center (2000, 1500), box x:[1900..2100], y:[1400..1600] -> raw (-1000, +500), size 200x200
        points[2] = .init(width: 200, height: 200, x: -1000, y: 500)
        // Point 18 (word 1, bit 2): center (4200, 2600), box x:[4050..4350], y:[2500..2700] -> raw (+1200, -600), size 300x200
        points[18] = .init(width: 300, height: 200, x: 1200, y: -600)

        let words = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 20,
            validAFPoints: 20,
            afImageExtent: (6000, 4000),
            points: points,
            inFocusIndices: [2, 18]
        )
        let report = try reader.read(
            data: VendorContainerBuilder.canonCR3(afWords: words)
        )
        #expect(report.status == .verifiedVendorFocusMetadata)
        guard case .region(let region)? = report.focus?.geometry else {
            Issue.record("Expected multi-point union region")
            return
        }
        // Combined minX=1900, maxX=4350 -> centerX=3125, width=2450
        // Combined minY=1400, maxY=2700 -> centerY=2050, height=1300
        #expect(region.center == ContinuousPoint(x: 3125, y: 2050))
        #expect(region.size == ContinuousSize(width: 2450, height: 1300))
    }

    @Test(
        "Falls back to PrimaryAFPoint when AFPointsInFocus is zero, else reports noRegionRecorded")
    func primaryAFPointFallbackAndManualFocus() throws {
        let points: [VendorContainerBuilder.CanonPoint] = [
            .init(width: 120, height: 80, x: -300, y: 200),
            .init(width: 140, height: 100, x: 400, y: -100),
        ]
        let primaryWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 2,
            validAFPoints: 2,
            afImageExtent: (6000, 4000),
            points: points,
            inFocusIndices: [],
            primaryAFPoint: 1
        )
        let primaryReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(afWords: primaryWords)
        )
        #expect(primaryReport.status == .verifiedVendorFocusMetadata)
        guard case .region(let primaryRegion)? = primaryReport.focus?.geometry else {
            Issue.record("Expected PrimaryAFPoint region")
            return
        }
        #expect(primaryRegion.center == ContinuousPoint(x: 3400, y: 2100))

        // Both AFPointsInFocus empty and PrimaryAFPoint == 0xFFFF
        let unsetWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 2,
            validAFPoints: 2,
            afImageExtent: (6000, 4000),
            points: points,
            inFocusIndices: [],
            primaryAFPoint: 0xFFFF
        )
        let unsetReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(afWords: unsetWords)
        )
        #expect(unsetReport.status == .verifiedVendorFocusMetadata)
        #expect(unsetReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .canon)))
        #expect(unsetReport.displayGeometry == nil)

        // ValidAFPoints == 0 (e.g. manual focus CR3)
        let mfWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 9,
            validAFPoints: 0,
            afImageExtent: (5472, 3648),
            points: []
        )
        let mfReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(
                imageExtent: (5472, 3648),
                afWords: mfWords
            )
        )
        #expect(mfReport.status == .verifiedVendorFocusMetadata)
        #expect(mfReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .canon)))
        #expect(mfReport.displayGeometry == nil)
    }

    @Test(
        "Decodes Canon 0x0026 across CR2/TIFF (LE & BE), JPEG, and HEIF with model-prefix fallback")
    func containersAndByteOrders() throws {
        let words = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 1,
            afImageExtent: (6000, 4000),
            points: [.init(width: 300, height: 200, x: 500, y: -300)],
            inFocusIndices: [0]
        )

        // Big-endian TIFF with Make omitted so "EOS R5" triggers Canon vendor detection
        let beTIFF = VendorContainerBuilder.canonTIFF(
            order: .bigEndian,
            make: nil,
            model: "EOS R5",
            orientation: 1,
            imageExtent: (6000, 4000),
            words: words
        )
        let tiffReport = try reader.read(data: Data(beTIFF))
        #expect(tiffReport.status == .verifiedVendorFocusMetadata)
        #expect(tiffReport.camera?.vendor == .canon)
        #expect(tiffReport.focus?.source == .canonMakerNoteAFInformation)
        guard case .region(let tiffRegion)? = tiffReport.focus?.geometry else {
            Issue.record("Expected region in BE TIFF")
            return
        }
        #expect(tiffRegion.center == ContinuousPoint(x: 3500, y: 2300))

        // JPEG wrapper around LE TIFF
        let leTIFF = VendorContainerBuilder.canonTIFF(
            order: .littleEndian,
            orientation: 6,
            imageExtent: (6000, 4000),
            words: words
        )
        let jpegReport = try reader.read(data: VendorContainerBuilder.jpeg(exifTIFF: leTIFF))
        #expect(jpegReport.status == .verifiedVendorFocusMetadata)
        #expect(jpegReport.container.kind == .jpeg)
        guard case .region(let jpegDisplay)? = jpegReport.displayGeometry else {
            Issue.record("Expected display region in JPEG")
            return
        }
        // Orient 6 (rotate90CW): stored (3500, 2300) in 6000x4000 -> (4000 - 2300, 3500) = (1700, 3500) in 4000x6000
        #expect(jpegDisplay.extent == PixelExtent(width: 4000, height: 6000))
        #expect(jpegDisplay.center == ContinuousPoint(x: 1700, y: 3500))
        #expect(jpegDisplay.size == ContinuousSize(width: 200, height: 300))

        // HEIF wrapper with irot = 3 (90 deg clockwise) and Exif Orientation omitted
        let heifTIFF = VendorContainerBuilder.canonTIFF(
            order: .littleEndian,
            orientation: nil,
            imageExtent: (6000, 4000),
            words: words
        )
        let heifReport = try reader.read(
            data: VendorContainerBuilder.heif(
                exifTIFF: heifTIFF, width: 6000, height: 4000, irot: 3)
        )
        #expect(heifReport.status == .verifiedVendorFocusMetadata)
        #expect(heifReport.container.kind == .heif)
        guard case .region(let heifDisplay)? = heifReport.displayGeometry else {
            Issue.record("Expected display region in HEIF")
            return
        }
        #expect(heifDisplay.extent == PixelExtent(width: 4000, height: 6000))
        #expect(heifDisplay.center == ContinuousPoint(x: 1700, y: 3500))
    }

    @Test("All 8 EXIF orientations transform Canon stored regions accurately")
    func allEightOrientations() throws {
        let words = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 1,
            afImageExtent: (4000, 3000),
            points: [.init(width: 400, height: 300, x: -1000, y: -700)],
            inFocusIndices: [0]
        )
        // Stored: center (2000 - 1000 = 1000, 1500 + 700 = 2200), size 400x300
        let storedExtent = try #require(PixelExtent(width: 4000, height: 3000))
        let storedCenter = ContinuousPoint(x: 1000, y: 2200)
        let storedSize = ContinuousSize(width: 400, height: 300)

        for raw in UInt16(1)...UInt16(8) {
            let exifOrient = try #require(ExifOrientation(rawValue: raw))
            let expected = exifOrient.transform.map(
                center: storedCenter,
                size: storedSize,
                storedExtent: storedExtent
            )
            let cr3 = VendorContainerBuilder.canonCR3(
                orientation: raw,
                imageExtent: (4000, 3000),
                afWords: words
            )
            let report = try reader.read(data: cr3)
            #expect(report.status == .verifiedVendorFocusMetadata)
            guard case .region(let display)? = report.displayGeometry else {
                Issue.record("Missing display geometry for orientation \(raw)")
                continue
            }
            #expect(display.extent == expected.extent)
            #expect(display.center == expected.center)
            #expect(display.size == expected.size)
        }
    }

    @Test(
        "Handles zero reference extent, mismatch, out-of-bounds centers, and malformed blocks cleanly"
    )
    func boundaryAndMalformedCases() throws {
        // 1. Zero AFImageWidth/Height
        let zeroRefWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 1,
            afImageExtent: (0, 4000),
            points: [.init(width: 100, height: 100, x: 0, y: 0)],
            inFocusIndices: [0]
        )
        let zeroRefReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(afWords: zeroRefWords)
        )
        #expect(zeroRefReport.status == .verifiedVendorFocusMetadata)
        #expect(zeroRefReport.focus?.geometry == .unavailable(.zeroReferenceExtent))

        // 2. Reference extent != imageExtent still yields verified region + advisory mismatch
        let mismatchWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 1,
            afImageExtent: (6720, 4480),
            points: [.init(width: 200, height: 200, x: 0, y: 0)],
            inFocusIndices: [0]
        )
        let mismatchReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(imageExtent: (3360, 2240), afWords: mismatchWords)
        )
        #expect(mismatchReport.status == .verifiedVendorFocusMetadata)
        #expect(mismatchReport.issues.contains { $0.kind == .referenceExtentMismatch })
        #expect(mismatchReport.uncertainties.contains(.referenceExtentMismatch))
        #expect(mismatchReport.displayGeometry != nil)

        // 3. Center outside reference extent
        let outsideWords = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 1,
            afImageExtent: (1000, 1000),
            points: [.init(width: 100, height: 100, x: 900, y: 0)],
            inFocusIndices: [0]
        )
        let outsideReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(imageExtent: (1000, 1000), afWords: outsideWords)
        )
        #expect(outsideReport.focus?.geometry == .unavailable(.centerOutsideReference))

        // 4. Declared byte count < actual payload stays unverified rawVendorObservation
        let smallerDeclared = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 1,
            afImageExtent: (6000, 4000),
            points: [.init(width: 100, height: 100, x: 0, y: 0)],
            inFocusIndices: [0],
            declaredBytesOverride: 8
        )
        let unverifiedReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(afWords: smallerDeclared)
        )
        #expect(unverifiedReport.status == .rawVendorObservation)
        #expect(
            unverifiedReport.focus?.geometry
                == .unavailable(.vendorSemanticsUnverified(vendor: .canon))
        )
        #expect(unverifiedReport.issues.contains { $0.kind == .unsupportedVendorFocusLayout })

        // 5. Declared byte count > actual payload -> malformed
        let truncatedDeclared = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 1,
            afImageExtent: (6000, 4000),
            points: [.init(width: 100, height: 100, x: 0, y: 0)],
            inFocusIndices: [0],
            declaredBytesOverride: 200
        )
        let truncatedReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(afWords: truncatedDeclared)
        )
        #expect(truncatedReport.status == .malformed)
        #expect(truncatedReport.issues.contains { $0.kind == .truncatedData })

        // 6. Invalid AF point counts (valid > num) -> malformed
        let invalidCounts = VendorContainerBuilder.canonAFInfoBlock(
            numAFPoints: 1,
            validAFPoints: 3,
            afImageExtent: (6000, 4000),
            points: [.init(width: 100, height: 100, x: 0, y: 0)]
        )
        let invalidCountsReport = try reader.read(
            data: VendorContainerBuilder.canonCR3(afWords: invalidCounts)
        )
        #expect(invalidCountsReport.status == .malformed)
        #expect(invalidCountsReport.issues.contains { $0.kind == .unexpectedFieldShape })

        // 7. Duplicate 0x0026 tag in CR3 CMT3 -> malformed
        let dupPayload = VendorContainerBuilder.encodeWords(smallerDeclared, order: .littleEndian)
        var boxBytes: [UInt8] = []
        let tiff = VendorContainerBuilder.singleIFDTIFF(
            order: .littleEndian,
            entries: [
                (0x0026, 3, UInt32(smallerDeclared.count), dupPayload),
                (0x0026, 3, UInt32(smallerDeclared.count), dupPayload),
            ]
        )
        func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            var b: [UInt8] = []
            TestSupport.appendUInt32(UInt32(8 + payload.count), to: &b, order: .bigEndian)
            b.append(contentsOf: type.utf8)
            b.append(contentsOf: payload)
            return b
        }
        let canonUUID: [UInt8] = [
            0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0,
            0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48,
        ]
        boxBytes += box("ftyp", Array("crx ".utf8) + [0, 0, 0, 1] + Array("crx isom".utf8))
        boxBytes += box("moov", box("uuid", canonUUID + box("CMT3", tiff)))
        let dupReport = try reader.read(data: Data(boxBytes))
        #expect(dupReport.status == .malformed)
        #expect(dupReport.issues.contains { $0.kind == .duplicateTag })
    }
}

private extension FocusRegionGeometry {
    func asDisplay(from region: FocusRegionGeometry) -> FocusRegionGeometry? {
        FocusRegionGeometry(
            space: .display,
            extent: region.extent,
            center: region.center,
            size: region.size
        )
    }
}

private extension FocusGeometry {
    var asRegion: FocusRegionGeometry? {
        if case .region(let r) = self { return r }
        return nil
    }
}
