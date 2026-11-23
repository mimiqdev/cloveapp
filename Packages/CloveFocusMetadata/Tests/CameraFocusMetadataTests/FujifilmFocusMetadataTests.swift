import Foundation
import Testing

@testable import CameraFocusMetadata

@Suite("Fujifilm Batch 1 AF metadata")
struct FujifilmFocusMetadataTests {
    private let reader = FocusMetadataReader()

    private func buildFujifilmTIFF(
        order: TIFFByteOrder = .littleEndian,
        make: String? = "FUJIFILM",
        model: String? = "X-S10",
        orientation: UInt16? = 1,
        imageExtent: (Int, Int)? = (4416, 2944),
        makerNote: [UInt8]
    ) -> [UInt8] {
        var builder = TestTIFFBuilder()
        builder.byteOrder = order
        builder.make = make
        builder.model = model
        builder.orientation = orientation
        builder.imageExtent = imageExtent
        builder.makerNote = makerNote
        return builder.build()
    }

    @Test("Decodes 0x1023 top-left FocusPixel against Exif, JPEG SOF, and HEIF ispe extents")
    func resolvesReferenceExtentAcrossContainers() throws {
        let makerNote = VendorContainerBuilder.fujifilmMakerNote(
            order: .littleEndian,
            focusMode: 0,
            focusPixel: (1281, 1163)
        )

        // 1. Exif 0xa002 / 0xa003 in TIFF/RAF-style IFD
        let tiffReport = try reader.read(
            data: Data(
                buildFujifilmTIFF(orientation: 1, imageExtent: (4416, 2944), makerNote: makerNote))
        )
        #expect(tiffReport.status == .verifiedVendorFocusMetadata)
        #expect(tiffReport.camera?.vendor == .fujifilm)
        #expect(tiffReport.focus?.source == .fujifilmFocusPixel)
        guard case .location(let stored)? = tiffReport.focus?.geometry else {
            Issue.record("Expected location geometry")
            return
        }
        #expect(stored.extent == PixelExtent(width: 4416, height: 2944))
        #expect(stored.center == ContinuousPoint(x: 1281, y: 1163))
        #expect(abs(stored.normalizedCenter.x - (1281.0 / 4416.0)) < 1e-9)
        #expect(abs(stored.normalizedCenter.y - (1163.0 / 2944.0)) < 1e-9)

        // 2. JPEG SOF fallback when Exif PixelX/Y are omitted
        let noExtentTIFF = buildFujifilmTIFF(
            orientation: 6,
            imageExtent: nil,
            makerNote: makerNote
        )
        let jpegReport = try reader.read(
            data: VendorContainerBuilder.jpeg(exifTIFF: noExtentTIFF, sofExtent: (4416, 2944))
        )
        #expect(jpegReport.status == .verifiedVendorFocusMetadata)
        #expect(jpegReport.imageExtent == PixelExtent(width: 4416, height: 2944))
        guard case .location(let jpegDisplay)? = jpegReport.displayGeometry else {
            Issue.record("Expected display geometry in JPEG SOF fallback")
            return
        }
        // Orient 6 (90 CW): stored (1281, 1163) on 4416x2944 -> (2944 - 1163 = 1781, 1281) on 2944x4416
        #expect(jpegDisplay.extent == PixelExtent(width: 2944, height: 4416))
        #expect(jpegDisplay.center == ContinuousPoint(x: 1781, y: 1281))

        // 3. HEIF ispe extent fallback + irot (when Exif Orientation and PixelX/Y are omitted)
        let heifNoExtentTIFF = buildFujifilmTIFF(
            orientation: nil,
            imageExtent: nil,
            makerNote: makerNote
        )
        let heifReport = try reader.read(
            data: VendorContainerBuilder.heif(
                exifTIFF: heifNoExtentTIFF,
                width: 4416,
                height: 2944,
                irot: 1
            )
        )
        #expect(heifReport.status == .verifiedVendorFocusMetadata)
        #expect(heifReport.imageExtent == PixelExtent(width: 4416, height: 2944))
        guard case .location(let heifDisplay)? = heifReport.displayGeometry else {
            Issue.record("Expected display location in HEIF")
            return
        }
        // irot=1 (270 CW / Orient 8): stored (1281, 1163) -> (1163, 4416 - 1281 = 3135) on 2944x4416
        #expect(heifDisplay.extent == PixelExtent(width: 2944, height: 4416))
        #expect(heifDisplay.center == ContinuousPoint(x: 1163, y: 3135))
    }

    @Test(
        "Handles unresolved extent, manual focus (0x1021=1), missing 0x1023, out-of-bounds, and malformed MakerNote"
    )
    func unavailabilityAndMalformedStates() throws {
        let validMN = VendorContainerBuilder.fujifilmMakerNote(
            focusMode: 0,
            focusPixel: (1281, 1163)
        )

        // Missing Exif extent in plain TIFF (not JPEG/HEIF) -> unresolved extent -> rawVendorObservation
        let unresolvedReport = try reader.read(
            data: Data(buildFujifilmTIFF(imageExtent: nil, makerNote: validMN))
        )
        #expect(unresolvedReport.status == .rawVendorObservation)
        #expect(
            unresolvedReport.focus?.geometry
                == .unavailable(.referenceExtentUnresolved(vendor: .fujifilm))
        )
        #expect(unresolvedReport.displayGeometry == nil)

        // FocusMode == 1 (MF) even when 0x1023 is omitted or present -> noRegionRecorded
        let mfMN = VendorContainerBuilder.fujifilmMakerNote(
            focusMode: 1,
            focusPixel: (2208, 1472)
        )
        let mfReport = try reader.read(data: Data(buildFujifilmTIFF(makerNote: mfMN)))
        #expect(mfReport.status == .verifiedVendorFocusMetadata)
        #expect(mfReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .fujifilm)))
        #expect(mfReport.displayGeometry == nil)

        // FocusMode == 2 (unverified non-AF/non-MF value) -> vendorSemanticsUnverified
        let unknownModeMN = VendorContainerBuilder.fujifilmMakerNote(
            focusMode: 2,
            focusPixel: (2208, 1472)
        )
        let unknownModeReport = try reader.read(
            data: Data(buildFujifilmTIFF(makerNote: unknownModeMN)))
        #expect(unknownModeReport.status == .rawVendorObservation)
        #expect(
            unknownModeReport.focus?.geometry
                == .unavailable(.vendorSemanticsUnverified(vendor: .fujifilm))
        )

        // Missing 0x1023 while AF active -> noLocationRecorded
        let missingPixelMN = VendorContainerBuilder.fujifilmMakerNote(
            focusMode: 0,
            focusPixel: nil
        )
        let missingPixelReport = try reader.read(
            data: Data(buildFujifilmTIFF(makerNote: missingPixelMN))
        )
        #expect(missingPixelReport.status == .verifiedVendorFocusMetadata)
        #expect(missingPixelReport.focus?.geometry == .unavailable(.noLocationRecorded))

        // Out-of-bounds focusPixel -> centerOutsideReference
        let outsideMN = VendorContainerBuilder.fujifilmMakerNote(
            focusMode: 0,
            focusPixel: (5000, 1000)
        )
        let outsideReport = try reader.read(data: Data(buildFujifilmTIFF(makerNote: outsideMN)))
        #expect(outsideReport.status == .verifiedVendorFocusMetadata)
        #expect(outsideReport.focus?.geometry == .unavailable(.centerOutsideReference))

        // Out-of-bounds directory offset inside FUJIFILM MakerNote header -> malformed
        let badOffsetMN = VendorContainerBuilder.fujifilmMakerNote(directoryOffsetOverride: 4)
        let badOffsetReport = try reader.read(data: Data(buildFujifilmTIFF(makerNote: badOffsetMN)))
        #expect(badOffsetReport.status == .malformed)
        #expect(badOffsetReport.issues.contains { $0.kind == .offsetOutOfBounds })
    }

    @Test("All 8 EXIF orientations transform Fujifilm 0x1023 stored location accurately")
    func allEightOrientations() throws {
        let mn = VendorContainerBuilder.fujifilmMakerNote(
            focusMode: nil,
            focusPixel: (1000, 2200)
        )
        let storedExtent = try #require(PixelExtent(width: 4000, height: 3000))
        let storedCenter = ContinuousPoint(x: 1000, y: 2200)

        for raw in UInt16(1)...UInt16(8) {
            let orient = try #require(ExifOrientation(rawValue: raw))
            let expected = orient.transform.map(
                center: storedCenter,
                size: ContinuousSize(width: 0, height: 0),
                storedExtent: storedExtent
            )
            let tiff = buildFujifilmTIFF(
                orientation: raw,
                imageExtent: (4000, 3000),
                makerNote: mn
            )
            let report = try reader.read(data: Data(tiff))
            #expect(report.status == .verifiedVendorFocusMetadata)
            guard case .location(let display)? = report.displayGeometry else {
                Issue.record("Expected display location for orientation \(raw)")
                continue
            }
            #expect(display.extent == expected.extent)
            #expect(display.center == expected.center)
        }
    }
}
