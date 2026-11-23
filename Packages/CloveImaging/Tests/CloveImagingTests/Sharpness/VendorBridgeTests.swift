import Foundation
import Testing

@testable import CameraFocusMetadata
@testable import CloveImaging

@Suite("Canon, Nikon, and Fujifilm Batch 1 bridge tests")
struct VendorBridgeTests {
    private struct StaticMetadataSource: AutofocusMetadataReader.MetadataFileReading {
        let conclusion: AutofocusMetadataReader.FocusMetadataConclusion
        func readMetadataFile(at url: URL) -> AutofocusMetadataReader.FocusMetadataConclusion? {
            conclusion
        }
    }

    private static func makeReader(for report: FocusMetadataReport) -> AutofocusMetadataReader {
        AutofocusMetadataReader(
            metadataFiles: StaticMetadataSource(
                conclusion: AutofocusMetadataReader.conclusion(of: report)
            )
        )
    }

    private static func u16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func u32(_ v: UInt32) -> [UInt8] {
        [
            UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF),
            UInt8((v >> 24) & 0xFF),
        ]
    }
    private static func be32(_ v: UInt32) -> [UInt8] {
        [
            UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF),
            UInt8(v & 0xFF),
        ]
    }
    private static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(8 + payload.count)) + Array(type.utf8) + payload
    }
    private static func singleIFD(_ entries: [(UInt16, UInt16, UInt32, [UInt8])]) -> [UInt8] {
        var bytes = [UInt8(0x49), 0x49, 0x2A, 0x00] + u32(8) + u16(UInt16(entries.count))
        var dataOffset = 8 + 2 + entries.count * 12 + 4
        var tail: [UInt8] = []
        for (tag, type, count, val) in entries {
            bytes += u16(tag) + u16(type) + u32(count)
            if val.count <= 4 {
                bytes += val + Array(repeating: 0, count: 4 - val.count)
            } else {
                bytes += u32(UInt32(dataOffset))
                tail += val
                dataOffset += val.count
            }
        }
        return bytes + u32(0) + tail
    }

    // Minimal self-contained Canon CMT3 CR3 builder for CloveImaging bridge verification.
    private static func canonCR3Data(
        orientation: UInt16 = 1,
        afImageExtent: (UInt16, UInt16) = (4000, 3000),
        rawX: Int16 = -1000,
        rawY: Int16 = -700,
        pointWidth: UInt16 = 400,
        pointHeight: UInt16 = 300,
        validAFPoints: UInt16 = 1
    ) -> Data {
        let words: [UInt16] = [
            32, 0, 1, validAFPoints,
            afImageExtent.0, afImageExtent.1, afImageExtent.0, afImageExtent.1,
            pointWidth, pointHeight, UInt16(bitPattern: rawX), UInt16(bitPattern: rawY),
            1, 1, 0, 0xFFFF,
        ]
        var wordBytes: [UInt8] = []
        for w in words { wordBytes += u16(w) }

        let cmt1 = box(
            "CMT1",
            singleIFD([
                (0x010F, 2, 6, Array("Canon\0".utf8)),
                (0x0110, 2, 13, Array("Canon EOS R5\0".utf8)),
                (0x0112, 3, 1, u16(orientation)),
            ])
        )
        let cmt2 = box(
            "CMT2",
            singleIFD([
                (0xA002, 4, 1, u32(UInt32(afImageExtent.0))),
                (0xA003, 4, 1, u32(UInt32(afImageExtent.1))),
            ])
        )
        let cmt3 = box("CMT3", singleIFD([(0x0026, 3, UInt32(words.count), wordBytes)]))
        let uuid: [UInt8] = [
            0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0,
            0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48,
        ]
        let ftyp = box("ftyp", Array("crx ".utf8) + [0, 0, 0, 1] + Array("crx isom".utf8))
        let moov = box("moov", box("uuid", uuid + cmt1 + cmt2 + cmt3))
        return Data(ftyp + moov)
    }

    private static func nikonNEFData(
        model: String = "NIKON Z 8",
        version: String = "0400",
        orientation: UInt16 = 1,
        afImage: (UInt16, UInt16) = (6000, 4000),
        area: (UInt16, UInt16, UInt16, UInt16) = (1800, 1200, 600, 400)
    ) -> Data {
        var block = [UInt8](repeating: 0, count: version.hasPrefix("04") ? 74 : 84)
        let verBytes = Array(version.utf8)
        for i in 0..<min(4, verBytes.count) { block[i] = verBytes[i] }
        if version == "0400" {
            let values = [afImage.0, afImage.1, area.0, area.1, area.2, area.3]
            for (idx, v) in values.enumerated() {
                let bytes = u16(v)
                block[62 + idx * 2] = bytes[0]
                block[62 + idx * 2 + 1] = bytes[1]
            }
        }
        let mnIFD = singleIFD([(0x00B7, 7, UInt32(block.count), block)])
        let makerNote: [UInt8] =
            [0x4E, 0x69, 0x6B, 0x6F, 0x6E, 0x00, 0x02, 0x10, 0x00, 0x00] + mnIFD

        let makeBytes = Array("NIKON CORPORATION\0".utf8)
        let modelBytes = Array((model + "\0").utf8)
        // IFD0 + ExifIFD
        let ifd0Count = 4
        let exifStart = 8 + 2 + ifd0Count * 12 + 4
        let exifTableSize = 2 + 12 + 4
        var outOffset = exifStart + exifTableSize
        let makeOff = outOffset
        outOffset += makeBytes.count
        let modelOff = outOffset
        outOffset += modelBytes.count
        let mnOff = outOffset

        var bytes = [UInt8(0x49), 0x49, 0x2A, 0x00] + u32(8) + u16(UInt16(ifd0Count))
        bytes += u16(0x010F) + u16(2) + u32(UInt32(makeBytes.count)) + u32(UInt32(makeOff))
        bytes += u16(0x0110) + u16(2) + u32(UInt32(modelBytes.count)) + u32(UInt32(modelOff))
        bytes += u16(0x0112) + u16(3) + u32(1) + u16(orientation) + [0, 0]
        bytes += u16(0x8769) + u16(4) + u32(1) + u32(UInt32(exifStart))
        bytes += u32(0)

        bytes += u16(1)
        bytes += u16(0x927C) + u16(7) + u32(UInt32(makerNote.count)) + u32(UInt32(mnOff))
        bytes += u32(0)

        bytes += makeBytes + modelBytes + makerNote
        return Data(bytes)
    }

    private static func fujifilmTIFFData(imageExtent: (UInt32, UInt32)? = (4416, 2944)) -> Data {
        var mn = Array("FUJIFILM".utf8) + u32(12)
        mn += u16(2)
        mn += u16(0x1021) + u16(3) + u32(1) + u16(0) + [0, 0]
        mn += u16(0x1023) + u16(3) + u32(2) + u16(1281) + u16(1163)
        mn += u32(0)

        let makeBytes = Array("FUJIFILM\0".utf8)
        let modelBytes = Array("X-S10\0".utf8)
        let ifd0Count = 4
        let exifEntriesCount = imageExtent == nil ? 1 : 3
        let exifStart = 8 + 2 + ifd0Count * 12 + 4
        let exifTableSize = 2 + exifEntriesCount * 12 + 4
        var outOffset = exifStart + exifTableSize
        let makeOff = outOffset
        outOffset += makeBytes.count
        let modelOff = outOffset
        outOffset += modelBytes.count
        let mnOff = outOffset

        var bytes = [UInt8(0x49), 0x49, 0x2A, 0x00] + u32(8) + u16(UInt16(ifd0Count))
        bytes += u16(0x010F) + u16(2) + u32(UInt32(makeBytes.count)) + u32(UInt32(makeOff))
        bytes += u16(0x0110) + u16(2) + u32(UInt32(modelBytes.count)) + u32(UInt32(modelOff))
        bytes += u16(0x0112) + u16(3) + u32(1) + u16(1) + [0, 0]
        bytes += u16(0x8769) + u16(4) + u32(1) + u32(UInt32(exifStart))
        bytes += u32(0)

        bytes += u16(UInt16(exifEntriesCount))
        bytes += u16(0x927C) + u16(7) + u32(UInt32(mn.count)) + u32(UInt32(mnOff))
        if let imageExtent {
            bytes += u16(0xA002) + u16(4) + u32(1) + u32(imageExtent.0)
            bytes += u16(0xA003) + u16(4) + u32(1) + u32(imageExtent.1)
        }
        bytes += u32(0)

        bytes += makeBytes + modelBytes + mn
        return Data(bytes)
    }

    @Test(
        "Canon CR3 display geometry maps through bridge with zero double orientation across 1...8")
    func canonCR3BridgeAllOrientations() throws {
        let url = URL(fileURLWithPath: "/synthetic-canon.CR3")
        // Stored: (2000 - 1000 = 1000, 1500 + 700 = 2200) on 4000x3000 -> normalized center (0.25, 2200/3000), size (0.10, 0.10)
        let storedRegion = NormalizedRegion(
            x: 0.25 - 0.05,
            y: (2200.0 / 3000.0) - 0.05,
            width: 0.10,
            height: 0.10
        )

        for raw in UInt16(1)...UInt16(8) {
            let report = try FocusMetadataReader().read(data: Self.canonCR3Data(orientation: raw))
            let reader = Self.makeReader(for: report)
            // Properties pass Orientation too, proving CloveImaging does not double-rotate focusmeta displayGeometry.
            let properties: [String: Any] = ["{TIFF}": ["Make": "Canon", "Orientation": Int(raw)]]
            guard case .success(let located) = reader.regions(of: url, properties: properties)
            else {
                Issue.record("Expected Canon CR3 bridge region for orientation \(raw)")
                continue
            }
            let expected = storedRegion.oriented(forExifOrientation: Int(raw))
            #expect(abs(located.region.centerX - expected.centerX) < 1e-6)
            #expect(abs(located.region.centerY - expected.centerY) < 1e-6)
            #expect(abs(located.region.width - expected.width) < 1e-6)
            #expect(abs(located.region.height - expected.height) < 1e-6)
        }
    }

    @Test("Vendor unavailability reports specific Canon, Nikon, and Fujifilm evidence paths")
    func vendorUnavailabilityEvidence() throws {
        // 1. Canon MF -> focusmeta.CanonMakerNote ... noRegionRecorded
        let canonReport = try FocusMetadataReader().read(data: Self.canonCR3Data(validAFPoints: 0))
        guard
            case .failure(let canonEvidence) = Self.makeReader(for: canonReport).regions(
                of: URL(fileURLWithPath: "/"), properties: ["{TIFF}": ["Make": "Canon"]])
        else {
            Issue.record("Canon MF must report failure evidence")
            return
        }
        #expect(
            canonEvidence.inspected.contains {
                $0.path == "focusmeta.CanonMakerNote Canon EOS R5" && $0.finding != .missing
            }
        )

        // 2. Nikon unverified DSLR -> focusmeta.NikonMakerNote ... vendorSemanticsUnverified
        let nikonReport = try FocusMetadataReader().read(
            data: Self.nikonNEFData(model: "NIKON D500", version: "0101")
        )
        guard
            case .failure(let nikonEvidence) = Self.makeReader(for: nikonReport).regions(
                of: URL(fileURLWithPath: "/"),
                properties: ["{TIFF}": ["Make": "NIKON CORPORATION"]])
        else {
            Issue.record("Nikon unverified DSLR must report failure evidence")
            return
        }
        #expect(
            nikonEvidence.inspected.contains {
                $0.path == "focusmeta.NikonMakerNote NIKON D500" && $0.finding != .missing
            }
        )

        // 3. Fujifilm unresolved extent -> focusmeta.FujifilmMakerNote ... referenceExtentUnresolved
        let fujiReport = try FocusMetadataReader().read(
            data: Self.fujifilmTIFFData(imageExtent: nil)
        )
        guard
            case .failure(let fujiEvidence) = Self.makeReader(for: fujiReport).regions(
                of: URL(fileURLWithPath: "/"), properties: ["{TIFF}": ["Make": "FUJIFILM"]])
        else {
            Issue.record("Fujifilm unresolved extent must report failure evidence")
            return
        }
        #expect(
            fujiEvidence.inspected.contains {
                $0.path == "focusmeta.FujifilmMakerNote X-S10" && $0.finding != .missing
            }
        )
    }

    @Test("Nikon Z verified display region and Fujifilm 0x1023 location map through bridge")
    func nikonAndFujifilmDisplayMapping() throws {
        // Verified Nikon Z display region maps directly into NormalizedRegion
        let nikonReport = try FocusMetadataReader().read(
            data: Self.nikonNEFData(
                model: "NIKON Z 8",
                version: "0400",
                orientation: 8,
                afImage: (6000, 4000),
                area: (1800, 1200, 600, 400)
            )
        )
        guard
            case .success(let nikonLocated) = Self.makeReader(for: nikonReport).regions(
                of: URL(fileURLWithPath: "/"),
                properties: ["{TIFF}": ["Make": "NIKON CORPORATION", "Orientation": 8]])
        else {
            Issue.record("Expected Nikon Z region through bridge")
            return
        }
        // Stored (1800, 1200) on 6000x4000 -> normalized (0.30, 0.30), size (0.10, 0.10).
        // Orient 8 (270 deg CW): displayCenter = (y, 1 - x) = (0.30, 0.70), displaySize = (0.10, 0.10).
        #expect(abs(nikonLocated.region.centerX - 0.30) < 1e-6)
        #expect(abs(nikonLocated.region.centerY - 0.70) < 1e-6)
        #expect(abs(nikonLocated.region.width - 0.10) < 1e-6)
        #expect(abs(nikonLocated.region.height - 0.10) < 1e-6)

        // Verified Fujifilm 0x1023 location maps to locatedRegionSize box centered at normalizedCenter
        let fujiReport = try FocusMetadataReader().read(
            data: Self.fujifilmTIFFData(imageExtent: (4416, 2944))
        )
        guard
            case .success(let fujiLocated) = Self.makeReader(for: fujiReport).regions(
                of: URL(fileURLWithPath: "/"), properties: [:])
        else {
            Issue.record("Expected Fujifilm location box through bridge")
            return
        }
        #expect(abs(fujiLocated.region.centerX - (1281.0 / 4416.0)) < 1e-6)
        #expect(abs(fujiLocated.region.centerY - (1163.0 / 2944.0)) < 1e-6)
        #expect(abs(fujiLocated.region.width - AutofocusMetadataReader.locatedRegionSize) < 1e-6)
        #expect(abs(fujiLocated.region.height - AutofocusMetadataReader.locatedRegionSize) < 1e-6)
    }
}
