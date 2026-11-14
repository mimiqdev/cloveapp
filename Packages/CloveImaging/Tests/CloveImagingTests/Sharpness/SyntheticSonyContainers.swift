import Foundation
@testable import CameraFocusMetadata
@testable import CloveImaging

/// Minimal synthetic metadata containers for the bridge tests: exactly the structures
/// focusmeta's verified scope reads, small enough to build in memory, independent of the
/// private sample files (#238). The layouts follow the sanitized handoff vectors: an ARW is a
/// classic little-endian TIFF whose Sony MakerNote directory sits directly at the payload,
/// and an HIF is an ISO-BMFF file whose Exif item payload embeds the same TIFF behind a
/// `SONY DSC ` prefix and is associated to the primary item with `cdsc`.
///
/// Out-of-line TIFF values are addressed relative to the enclosing TIFF header: absolute in
/// the file for an ARW, and relative to the embedded header for the Exif item of an HIF. The
/// Sony MakerNote directory inherits that context, so its values are addressed the same way —
/// which is what the real cameras write and the vendored parser reads.
enum SyntheticSonyContainer {
    // MARK: Low-level little-endian writing

    private static func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }
    private static func u32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }

    private struct Entry {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let value: [UInt8]

        init(tag: UInt16, type: UInt16, count: UInt32, value: [UInt8]) {
            self.tag = tag
            self.type = type
            self.count = count
            self.value = value
        }

        init(tag: UInt16, ascii: String) {
            var bytes = Array(ascii.utf8)
            bytes.append(0)
            self.init(tag: tag, type: 2, count: UInt32(bytes.count), value: bytes)
        }

        /// A SHORT[1] value, inline.
        init(tag: UInt16, word: UInt16) {
            self.init(tag: tag, type: 3, count: 1, value: u16(word))
        }
    }

    /// One directory table plus its out-of-line data. `dataBase` is the absolute offset the
    /// directory's own value offsets are expressed against.
    private static func directory(_ entries: [Entry], dataBase: Int) -> [UInt8] {
        let tableSize = 2 + entries.count * 12 + 4
        var valueOffset = dataBase + tableSize
        var valueBytes: [UInt8] = []
        var bytes = u16(UInt16(entries.count))
        for entry in entries {
            bytes += u16(entry.tag) + u16(entry.type) + u32(entry.count)
            if entry.value.count <= 4 {
                bytes += entry.value + Array(repeating: 0, count: 4 - entry.value.count)
            } else {
                bytes += u32(UInt32(valueOffset))
                valueBytes += entry.value
                valueOffset += entry.value.count
            }
        }
        bytes += u32(0)
        bytes += valueBytes
        return bytes
    }

    // MARK: The Sony MakerNote

    /// The Sony MakerNote payload: an unprefixed directory for ARW, or the `SONY DSC `-prefixed
    /// form for HIF, carrying exactly the verified focus tags. `location` is
    /// (width, height, centerX, centerY); `frame` is (width, height, availability).
    /// `payloadBase` is the payload's offset in the addressing space of the enclosing TIFF.
    static func sonyMakerNote(
        location: (UInt16, UInt16, UInt16, UInt16)? = (80, 60, 17, 31),
        frame: (UInt16, UInt16, UInt16)? = (10, 6, 257),
        mode: UInt8 = 3,
        prefixed: Bool = false,
        payloadBase: Int
    ) -> [UInt8] {
        var entries: [Entry] = []
        // Type 1 (BYTE), count 1, inline: the shapes the real tags carry.
        entries.append(Entry(tag: 0x201B, type: 1, count: 1, value: [mode]))
        entries.append(Entry(tag: 0x201C, type: 1, count: 1, value: [0]))
        if let location {
            entries.append(
                Entry(
                    tag: 0x2027, type: 3, count: 4,
                    value: u16(location.0) + u16(location.1) + u16(location.2) + u16(location.3)))
        }
        if let frame {
            // Type 7 (UNDEFINED), six raw bytes: little-endian width, height, availability.
            entries.append(
                Entry(
                    tag: 0x2037, type: 7, count: 6,
                    value: u16(frame.0) + u16(frame.1) + u16(frame.2)))
        }
        entries.sort { $0.tag < $1.tag }
        let prefix = prefixed ? Array("SONY DSC ".utf8) + [0, 0, 0] : []
        return prefix + directory(entries, dataBase: payloadBase + prefix.count)
    }

    // MARK: The classic TIFF (ARW, and the HIF's embedded Exif item)

    /// Builds the TIFF and reports where the MakerNote payload landed in the file, so a
    /// second pass can rebuild the payload with TIFF-absolute value offsets. The payload's
    /// length does not depend on the base, so both passes share one layout.
    private static func tiff(
        make: String?, model: String?, orientation: UInt16?, extent: (Int, Int)?,
        makerNoteBase: Int, makerNote: (Int) -> [UInt8]
    ) -> (bytes: [UInt8], makerNoteOffset: Int?) {
        var ifd0: [Entry] = []
        if let make { ifd0.append(Entry(tag: 0x010F, ascii: make)) }
        if let model { ifd0.append(Entry(tag: 0x0110, ascii: model)) }
        if let orientation { ifd0.append(Entry(tag: 0x0112, word: orientation)) }

        let payload = makerNote(makerNoteBase)
        var exif: [Entry] = []
        if let extent {
            exif.append(Entry(tag: 0xA002, type: 4, count: 1, value: u32(UInt32(extent.0))))
            exif.append(Entry(tag: 0xA003, type: 4, count: 1, value: u32(UInt32(extent.1))))
        }
        var makerNoteOffset: Int?
        if !payload.isEmpty {
            exif.append(Entry(tag: 0x927C, type: 7, count: UInt32(payload.count), value: payload))
        }
        if !exif.isEmpty {
            // The Exif pointer's value is patched below once the offset is known.
            ifd0.append(Entry(tag: 0x8769, type: 4, count: 1, value: u32(0)))
        }

        func tableSize(_ entries: [Entry]) -> Int { 2 + entries.count * 12 + 4 }
        let ifd0Offset = 8
        let exifOffset = ifd0Offset + tableSize(ifd0)
        let dataStart = exifOffset + (exif.isEmpty ? 0 : tableSize(exif))

        // Out-of-line data follows the tables, in entry order.
        var dataOffset = dataStart
        var ifd0Data: [Int: Int] = [:]
        var exifData: [Int: Int] = [:]
        for (index, entry) in ifd0.enumerated() where entry.value.count > 4 {
            ifd0Data[index] = dataOffset
            dataOffset += entry.value.count
        }
        for (index, entry) in exif.enumerated() where entry.value.count > 4 {
            exifData[index] = dataOffset
            if entry.tag == 0x927C { makerNoteOffset = dataOffset }
            dataOffset += entry.value.count
        }
        if let pointer = ifd0.firstIndex(where: { $0.tag == 0x8769 }) {
            ifd0[pointer] = Entry(tag: 0x8769, type: 4, count: 1, value: u32(UInt32(exifOffset)))
        }

        var bytes: [UInt8] = [0x49, 0x49] + u16(42) + u32(8)
        writeTable(ifd0, into: &bytes, dataOffsets: ifd0Data)
        if !exif.isEmpty { writeTable(exif, into: &bytes, dataOffsets: exifData) }
        for entry in ifd0 where entry.value.count > 4 { bytes += entry.value }
        for entry in exif where entry.value.count > 4 { bytes += entry.value }
        return (bytes, makerNoteOffset)
    }

    /// The two-pass build: the payload's own value offsets are TIFF-absolute, so the first
    /// pass discovers where the payload lands and the second writes the real offsets.
    private static func tiffWithSonyMakerNote(
        make: String?, model: String?, orientation: UInt16?, extent: (Int, Int)?,
        location: (UInt16, UInt16, UInt16, UInt16)?, frame: (UInt16, UInt16, UInt16)?,
        prefixed: Bool
    ) -> [UInt8] {
        func payload(_ base: Int) -> [UInt8] {
            location == nil && frame == nil
                ? []
                : sonyMakerNote(
                    location: location, frame: frame, prefixed: prefixed, payloadBase: base)
        }
        let probe = tiff(
            make: make, model: model, orientation: orientation, extent: extent,
            makerNoteBase: 0, makerNote: payload)
        let base = probe.makerNoteOffset ?? 0
        return tiff(
            make: make, model: model, orientation: orientation, extent: extent,
            makerNoteBase: base, makerNote: payload
        ).bytes
    }

    private static func writeTable(
        _ entries: [Entry], into bytes: inout [UInt8], dataOffsets: [Int: Int]
    ) {
        bytes += u16(UInt16(entries.count))
        for (index, entry) in entries.enumerated() {
            bytes += u16(entry.tag) + u16(entry.type) + u32(entry.count)
            if entry.value.count <= 4 {
                bytes += entry.value + Array(repeating: 0, count: 4 - entry.value.count)
            } else {
                bytes += u32(UInt32(dataOffsets[index] ?? 0))
            }
        }
        bytes += u32(0)
    }

    // MARK: Public container builders

    /// A synthetic JPEG with an APP1 Exif segment: SOI, APP1 (`Exif\0\0` + TIFF), SOS, EOI.
    /// The TIFF carries whatever make/model and maker note it is given, so a non-Sony maker
    /// note exercises focusmeta's raw-observation path for that vendor.
    static func jpeg(
        make: String?, model: String?, makerNote: [UInt8]?
    ) -> Data {
        let tiff = tiff(
            make: make, model: model, orientation: nil, extent: nil,
            makerNoteBase: 0, makerNote: { _ in makerNote ?? [] })
        var app1 = Array("Exif".utf8) + [0, 0] + tiff.bytes
        // Segment length is the payload plus the 2 length bytes themselves.
        var lengthBytes = [UInt8((app1.count + 2) >> 8), UInt8((app1.count + 2) & 0xFF)]
        var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1] + lengthBytes + app1
        bytes += [0xFF, 0xDA, 0x00, 0x02]  // SOS with empty payload
        bytes += [0xFF, 0xD9]  // EOI
        lengthBytes = []
        app1 = []
        return Data(bytes)
    }

    /// A synthetic ARW-shaped file: classic little-endian TIFF with an unprefixed Sony
    /// MakerNote directory whose value offsets are TIFF-absolute, the way the ARW layout
    /// reads them.
    static func arw(
        make: String? = "SONY",
        model: String? = "ILCE-1M2",
        orientation: UInt16? = 1,
        extent: (Int, Int)? = (80, 60),
        location: (UInt16, UInt16, UInt16, UInt16)? = (80, 60, 17, 31),
        frame: (UInt16, UInt16, UInt16)? = (10, 6, 257)
    ) -> Data {
        Data(
            tiffWithSonyMakerNote(
                make: make, model: model, orientation: orientation, extent: extent,
                location: location, frame: frame, prefixed: false))
    }

    /// A synthetic HIF-shaped file: ISO-BMFF with `meta`/`iloc` describing one Exif item whose
    /// payload embeds the same TIFF behind `SONY DSC `, `pitm` naming a primary grid item,
    /// `cdsc` linking Exif to primary, and `irot` carrying the primary-image rotation. The
    /// embedded TIFF's header is the addressing base for its MakerNote's offsets.
    static func heif(
        make: String? = "SONY",
        model: String? = "ILCE-1M2",
        extent: (Int, Int)? = (80, 60),
        location: (UInt16, UInt16, UInt16, UInt16)? = (80, 60, 17, 31),
        frame: (UInt16, UInt16, UInt16)? = (10, 6, 257),
        irot: UInt8? = 1
    ) -> Data {
        let exifTIFF = tiffWithSonyMakerNote(
            make: make, model: model, orientation: nil, extent: extent,
            location: location, frame: frame, prefixed: true)
        return Data(heifContainer(exifTIFF: exifTIFF, extent: extent, irot: irot))
    }

    // MARK: ISO-BMFF writing (big-endian)

    private static func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }
    private static func be16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }
    private static func fullBoxPayload(version: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [version, 0, 0, 0] + payload
    }
    private static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(8 + payload.count)) + Array(type.utf8) + payload
    }
    private static func fullBox(_ type: String, version: UInt8 = 0, _ payload: [UInt8]) -> [UInt8] {
        box(type, fullBoxPayload(version: version, payload))
    }

    private static func heifContainer(
        exifTIFF: [UInt8], extent: (Int, Int)?, irot: UInt8?
    ) -> [UInt8] {
        let primaryItem: UInt16 = 30
        let exifItem: UInt16 = 14

        let ftyp = Array("heix".utf8) + [0, 0, 0, 0] + Array("mif1".utf8) + Array("heix".utf8)
        let pitm = be16(primaryItem)

        func infe(_ id: UInt16, _ type: String) -> [UInt8] {
            var payload = be16(id) + be16(0) + Array(type.utf8)
            payload.append(0)
            return box("infe", fullBoxPayload(version: 2, payload))
        }
        let iinfPayload =
            be16(3) + infe(exifItem, "Exif") + infe(primaryItem, "grid") + infe(31, "hvc1")
        let cdsc = be16(exifItem) + be16(1) + be16(primaryItem)

        var properties: [[UInt8]] = []
        if let extent {
            properties.append(
                box(
                    "ispe",
                    fullBoxPayload(
                        version: 0, be32(UInt32(extent.0)) + be32(UInt32(extent.1)))))
        }
        if let irot {
            properties.append(box("irot", [irot]))
        }
        var ipcoPayload: [UInt8] = []
        for property in properties { ipcoPayload += property }

        var ipmaPayload = be32(1) + be16(primaryItem) + [UInt8(properties.count)]
        for index in 1...properties.count { ipmaPayload.append(UInt8(index)) }
        let iprp = box("iprp", box("ipco", ipcoPayload) + fullBox("ipma", ipmaPayload))

        // The Exif item's payload: 32-bit displacement, "Exif\0\0", then the TIFF.
        let exifPayload = be32(6) + Array("Exif".utf8) + [0, 0] + exifTIFF

        var ilocPayload: [UInt8] = [0x44, 0x00]
        ilocPayload += be16(1) + be16(exifItem) + be16(0) + be16(0) + be16(1)
        let extentOffsetPosition = ilocPayload.count
        ilocPayload += be32(0) + be32(UInt32(exifPayload.count))

        func buildMeta(exifOffset: UInt32) -> [UInt8] {
            var patched = ilocPayload
            patched.replaceSubrange(
                extentOffsetPosition..<(extentOffsetPosition + 4), with: be32(exifOffset))
            let metaPayload =
                fullBox("pitm", pitm) + fullBox("iinf", iinfPayload)
                + fullBox("iloc", version: 1, patched)
                + fullBox("iref", box("cdsc", cdsc)) + iprp
            return fullBox("meta", metaPayload)
        }

        // Resolve the extent offset: meta comes first, then padding to a fixed point, then mdat.
        let probeContainer = box("ftyp", ftyp) + buildMeta(exifOffset: 0)
        let containerOffset = max(4096, probeContainer.count + 32)
        let meta = buildMeta(exifOffset: UInt32(containerOffset + 8))
        var output = box("ftyp", ftyp) + meta
        let padding = containerOffset - output.count
        if padding > 8 {
            output += box("free", Array(repeating: 0, count: padding - 8))
        }
        output += box("mdat", exifPayload)
        return output
    }
}
