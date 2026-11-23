import Foundation
import Testing

@testable import CameraFocusMetadata

@Suite("Nikon Batch 1 AF metadata")
struct NikonFocusMetadataTests {
    private let reader = FocusMetadataReader()

    private func buildNikonTIFF(
        order: TIFFByteOrder = .littleEndian,
        make: String? = "NIKON CORPORATION",
        model: String? = "NIKON Z 6",
        orientation: UInt16? = 1,
        imageExtent: (Int, Int)? = nil,
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

    @Test(
        "Decodes verified continuous AF area across 0300, 0301, 0400, 0401, 0402, and 0100 ContrastDetect"
    )
    func verifiedVersionsDecodeContinuousRegions() throws {
        let versions = ["0300", "0301", "0400", "0401", "0402", "0100"]
        for version in versions {
            let makerNote = VendorContainerBuilder.nikonMakerNote(
                order: .littleEndian,
                version: version,
                contrastDetectByte: 1,
                afImageExtent: (6000, 4000),
                area: (x: 1800, y: 1200, width: 300, height: 240)
            )
            let tiff = buildNikonTIFF(orientation: 1, makerNote: makerNote)
            let report = try reader.read(data: Data(tiff))
            #expect(report.status == .verifiedVendorFocusMetadata, Comment(rawValue: version))
            #expect(report.camera?.vendor == .nikon)
            #expect(report.focus?.source == .nikonAFInformation)
            guard case .region(let stored)? = report.focus?.geometry else {
                Issue.record("Expected region for Nikon 0x00b7 v\(version)")
                continue
            }
            #expect(stored.extent == PixelExtent(width: 6000, height: 4000))
            #expect(stored.center == ContinuousPoint(x: 1800, y: 1200))
            #expect(stored.size == ContinuousSize(width: 300, height: 240))
            guard case .region(let display)? = report.displayGeometry else {
                Issue.record("Expected display region for Nikon 0x00b7 v\(version)")
                continue
            }
            #expect(display.center == stored.center)
            #expect(display.size == stored.size)
        }
    }

    @Test("Big-endian Nikon NEF and JPEG/HEIF containers decode 0x00b7 accurately")
    func byteOrdersAndContainers() throws {
        // Big-endian MakerNote (e.g. older ContrastDetect or big-endian NEF)
        let beMN = VendorContainerBuilder.nikonMakerNote(
            order: .bigEndian,
            version: "0300",
            afImageExtent: (5568, 3712),
            area: (x: 3776, y: 1741, width: 552, height: 552)
        )
        let beTIFF = buildNikonTIFF(
            order: .bigEndian,
            model: "NIKON Z 30",
            orientation: 8,
            makerNote: beMN
        )
        let nefReport = try reader.read(data: Data(beTIFF))
        #expect(nefReport.status == .verifiedVendorFocusMetadata)
        guard case .region(let displayNEF)? = nefReport.displayGeometry else {
            Issue.record("Expected display geometry for BE NEF")
            return
        }
        // Orient 8 (rotate270Clockwise): (x=y=1741, y=W-x=5568-3776=1792), extent 3712x5568
        #expect(displayNEF.extent == PixelExtent(width: 3712, height: 5568))
        #expect(displayNEF.center == ContinuousPoint(x: 1741, y: 1792))

        // JPEG wrapper
        let jpeg = VendorContainerBuilder.jpeg(exifTIFF: beTIFF)
        let jpegReport = try reader.read(data: jpeg)
        #expect(jpegReport.status == .verifiedVendorFocusMetadata)
        #expect(jpegReport.container.kind == .jpeg)
        #expect(jpegReport.displayGeometry == nefReport.displayGeometry)

        // HEIF wrapper with irot = 1 (270 deg CW, same display transform as Orient 8) and no Exif Orientation
        let leMN = VendorContainerBuilder.nikonMakerNote(
            order: .littleEndian,
            version: "0400",
            afImageExtent: (5568, 3712),
            area: (x: 3776, y: 1741, width: 552, height: 552)
        )
        let heifTIFF = buildNikonTIFF(orientation: nil, makerNote: leMN)
        let heif = VendorContainerBuilder.heif(
            exifTIFF: heifTIFF,
            width: 5568,
            height: 3712,
            irot: 1
        )
        let heifReport = try reader.read(data: heif)
        #expect(heifReport.status == .verifiedVendorFocusMetadata)
        #expect(heifReport.container.kind == .heif)
        #expect(heifReport.displayGeometry == nefReport.displayGeometry)
    }

    @Test(
        "Zero width or height emits location; all-zero emits noRegionRecorded; unverified DSLR stays raw"
    )
    func pointZeroAllZeroAndUnverifiedVersions() throws {
        // Point-only location (width == 0, height == 0, non-zero center)
        let locMN = VendorContainerBuilder.nikonMakerNote(
            version: "0300",
            afImageExtent: (6000, 4000),
            area: (x: 1500, y: 2500, width: 0, height: 0)
        )
        let locReport = try reader.read(data: Data(buildNikonTIFF(makerNote: locMN)))
        #expect(locReport.status == .verifiedVendorFocusMetadata)
        guard case .location(let loc)? = locReport.focus?.geometry else {
            Issue.record("Expected location when area width/height are 0")
            return
        }
        #expect(loc.center == ContinuousPoint(x: 1500, y: 2500))

        // All-zero area inside valid AFImageExtent -> noRegionRecorded
        let noAreaMN = VendorContainerBuilder.nikonMakerNote(
            version: "0400",
            afImageExtent: (6000, 4000),
            area: (x: 0, y: 0, width: 0, height: 0)
        )
        let noAreaReport = try reader.read(data: Data(buildNikonTIFF(makerNote: noAreaMN)))
        #expect(noAreaReport.status == .verifiedVendorFocusMetadata)
        #expect(noAreaReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .nikon)))
        #expect(noAreaReport.displayGeometry == nil)

        // All six fields zero -> noRegionRecorded
        let allZeroMN = VendorContainerBuilder.nikonMakerNote(
            version: "0400",
            afImageExtent: (0, 0),
            area: (x: 0, y: 0, width: 0, height: 0)
        )
        let allZeroReport = try reader.read(data: Data(buildNikonTIFF(makerNote: allZeroMN)))
        #expect(allZeroReport.status == .verifiedVendorFocusMetadata)
        #expect(allZeroReport.focus?.geometry == .unavailable(.noRegionRecorded(vendor: .nikon)))

        // DSLR point-index versions remain rawVendorObservation + vendorSemanticsUnverified
        for (ver, cd) in [("0101", UInt8(0)), ("0100", 0), ("0200", 0), ("0201", 0)] {
            let mn = VendorContainerBuilder.nikonMakerNote(
                version: ver,
                contrastDetectByte: cd
            )
            let report = try reader.read(data: Data(buildNikonTIFF(makerNote: mn)))
            #expect(report.status == .rawVendorObservation, Comment(rawValue: ver))
            #expect(
                report.focus?.geometry
                    == .unavailable(.vendorSemanticsUnverified(vendor: .nikon))
            )
            #expect(report.displayGeometry == nil)
            #expect(report.uncertainties.contains(.vendorGeometryUnverified))
        }
    }

    @Test("All 8 EXIF orientations transform Nikon 0x00b7 regions accurately")
    func allEightOrientations() throws {
        let mn = VendorContainerBuilder.nikonMakerNote(
            version: "0300",
            afImageExtent: (4000, 3000),
            area: (x: 1000, y: 2200, width: 400, height: 300)
        )
        let storedExtent = try #require(PixelExtent(width: 4000, height: 3000))
        let storedCenter = ContinuousPoint(x: 1000, y: 2200)
        let storedSize = ContinuousSize(width: 400, height: 300)

        for raw in UInt16(1)...UInt16(8) {
            let orient = try #require(ExifOrientation(rawValue: raw))
            let expected = orient.transform.map(
                center: storedCenter,
                size: storedSize,
                storedExtent: storedExtent
            )
            let tiff = buildNikonTIFF(orientation: raw, makerNote: mn)
            let report = try reader.read(data: Data(tiff))
            #expect(report.status == .verifiedVendorFocusMetadata)
            guard case .region(let display)? = report.displayGeometry else {
                Issue.record("Expected display region for orientation \(raw)")
                continue
            }
            #expect(display.extent == expected.extent)
            #expect(display.center == expected.center)
            #expect(display.size == expected.size)
        }
    }

    @Test("Detects zero reference, mismatch, outside bounds, and truncated 0x00b7 blocks")
    func boundaryAndMalformedCases() throws {
        // Zero AFImage with non-zero area -> zeroReferenceExtent
        let zeroRefMN = VendorContainerBuilder.nikonMakerNote(
            version: "0300",
            afImageExtent: (0, 4000),
            area: (x: 100, y: 100, width: 50, height: 50)
        )
        let zeroRefReport = try reader.read(data: Data(buildNikonTIFF(makerNote: zeroRefMN)))
        #expect(zeroRefReport.focus?.geometry == .unavailable(.zeroReferenceExtent))

        // Extent mismatch with Exif imageExtent
        let mismatchMN = VendorContainerBuilder.nikonMakerNote(
            version: "0300",
            afImageExtent: (6000, 4000),
            area: (x: 3000, y: 2000, width: 400, height: 300)
        )
        let mismatchReport = try reader.read(
            data: Data(buildNikonTIFF(imageExtent: (3000, 2000), makerNote: mismatchMN))
        )
        #expect(mismatchReport.status == .verifiedVendorFocusMetadata)
        #expect(mismatchReport.issues.contains { $0.kind == .referenceExtentMismatch })
        #expect(mismatchReport.uncertainties.contains(.referenceExtentMismatch))

        // Center outside AFImage extent
        let outsideMN = VendorContainerBuilder.nikonMakerNote(
            version: "0400",
            afImageExtent: (1000, 1000),
            area: (x: 1200, y: 500, width: 100, height: 100)
        )
        let outsideReport = try reader.read(data: Data(buildNikonTIFF(makerNote: outsideMN)))
        #expect(outsideReport.focus?.geometry == .unavailable(.centerOutsideReference))

        // Truncated 0300 (<54), 0400 (<74), 0100 CD (<28) -> .malformed
        for (version, truncatedLen) in [("0300", 40), ("0400", 60), ("0100", 20)] {
            let truncatedMN = VendorContainerBuilder.nikonMakerNote(
                version: version,
                contrastDetectByte: 1,
                truncatedByteCount: truncatedLen
            )
            let report = try reader.read(data: Data(buildNikonTIFF(makerNote: truncatedMN)))
            #expect(report.status == .malformed, Comment(rawValue: version))
            #expect(report.issues.contains { $0.kind == .truncatedData })
        }
    }
}
