import Foundation
@testable import CameraFocusMetadata

/// Shared synthetic container and vendor-payload builders for Batch 1 unit tests.
enum VendorContainerBuilder {
    struct CanonPoint {
        let width: UInt16
        let height: UInt16
        let x: Int16
        let y: Int16
    }

    static func canonAFInfoBlock(
        order: TIFFByteOrder = .littleEndian,
        areaMode: UInt16 = 0,
        numAFPoints: UInt16,
        validAFPoints: UInt16,
        canonImageExtent: (UInt16, UInt16) = (6000, 4000),
        afImageExtent: (UInt16, UInt16) = (6000, 4000),
        points: [CanonPoint],
        inFocusIndices: [Int] = [],
        selectedIndices: [Int] = [],
        primaryAFPoint: UInt16? = nil,
        includeTailMasks: Bool = true,
        declaredBytesOverride: UInt16? = nil
    ) -> [UInt16] {
        let n = Int(numAFPoints)
        let maskWords = (n + 15) / 16
        var inFocus = [UInt16](repeating: 0, count: maskWords)
        for index in inFocusIndices where index >= 0 && index < n {
            inFocus[index / 16] |= UInt16(1) << (index % 16)
        }
        var selected = [UInt16](repeating: 0, count: maskWords)
        for index in selectedIndices where index >= 0 && index < n {
            selected[index / 16] |= UInt16(1) << (index % 16)
        }

        var widths = [UInt16](repeating: 0, count: n)
        var heights = [UInt16](repeating: 0, count: n)
        var xs = [UInt16](repeating: 0, count: n)
        var ys = [UInt16](repeating: 0, count: n)
        for (idx, pt) in points.enumerated() where idx < n {
            widths[idx] = pt.width
            heights[idx] = pt.height
            xs[idx] = UInt16(bitPattern: pt.x)
            ys[idx] = UInt16(bitPattern: pt.y)
        }

        var words: [UInt16] = [
            0,
            areaMode,
            numAFPoints,
            validAFPoints,
            canonImageExtent.0,
            canonImageExtent.1,
            afImageExtent.0,
            afImageExtent.1,
        ]
        words.append(contentsOf: widths)
        words.append(contentsOf: heights)
        words.append(contentsOf: xs)
        words.append(contentsOf: ys)
        words.append(contentsOf: inFocus)
        if includeTailMasks {
            words.append(contentsOf: selected)
            words.append(contentsOf: [UInt16](repeating: 0, count: maskWords))
            words.append(primaryAFPoint ?? 0xFFFF)
        }
        words[0] = declaredBytesOverride ?? UInt16(words.count * 2)
        return words
    }

    static func encodeWords(_ words: [UInt16], order: TIFFByteOrder) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(words.count * 2)
        for word in words {
            TestSupport.appendUInt16(word, to: &bytes, order: order)
        }
        return bytes
    }

    static func singleIFDTIFF(
        order: TIFFByteOrder = .littleEndian,
        entries: [(tag: UInt16, type: UInt16, count: UInt32, value: [UInt8])]
    ) -> [UInt8] {
        var bytes: [UInt8] =
            order == .littleEndian ? [0x49, 0x49, 0x2A, 0x00] : [0x4D, 0x4D, 0x00, 0x2A]
        TestSupport.appendUInt32(8, to: &bytes, order: order)
        let tableSize = 2 + entries.count * 12 + 4
        var dataOffset = 8 + tableSize
        var outOfLine: [UInt8] = []

        TestSupport.appendUInt16(UInt16(entries.count), to: &bytes, order: order)
        for entry in entries {
            TestSupport.appendUInt16(entry.tag, to: &bytes, order: order)
            TestSupport.appendUInt16(entry.type, to: &bytes, order: order)
            TestSupport.appendUInt32(entry.count, to: &bytes, order: order)
            if entry.value.count <= 4 {
                bytes.append(contentsOf: entry.value)
                bytes.append(contentsOf: Array(repeating: 0, count: 4 - entry.value.count))
            } else {
                TestSupport.appendUInt32(UInt32(dataOffset), to: &bytes, order: order)
                outOfLine.append(contentsOf: entry.value)
                dataOffset += entry.value.count
            }
        }
        TestSupport.appendUInt32(0, to: &bytes, order: order)
        bytes.append(contentsOf: outOfLine)
        return bytes
    }

    static func canonMakerNoteDirectory(
        order: TIFFByteOrder = .littleEndian,
        words: [UInt16],
        tiffBaseBeforeMakerNote: Int
    ) -> [UInt8] {
        let valueBytes = encodeWords(words, order: order)
        let entryCount: UInt16 = 1
        let tableSize = 2 + 12 + 4
        var bytes: [UInt8] = []
        TestSupport.appendUInt16(entryCount, to: &bytes, order: order)
        TestSupport.appendUInt16(0x0026, to: &bytes, order: order)
        TestSupport.appendUInt16(3, to: &bytes, order: order)
        TestSupport.appendUInt32(UInt32(words.count), to: &bytes, order: order)
        if valueBytes.count <= 4 {
            bytes.append(contentsOf: valueBytes)
            bytes.append(contentsOf: Array(repeating: 0, count: 4 - valueBytes.count))
            TestSupport.appendUInt32(0, to: &bytes, order: order)
        } else {
            let valueAbsoluteOffset = tiffBaseBeforeMakerNote + tableSize
            TestSupport.appendUInt32(UInt32(valueAbsoluteOffset), to: &bytes, order: order)
            TestSupport.appendUInt32(0, to: &bytes, order: order)
            bytes.append(contentsOf: valueBytes)
        }
        return bytes
    }

    /// Builds a classic Canon TIFF/CR2 container where the MakerNote IFD offsets are absolute within the TIFF.
    static func canonTIFF(
        order: TIFFByteOrder = .littleEndian,
        make: String? = "Canon",
        model: String? = "Canon EOS R5",
        orientation: UInt16? = 1,
        imageExtent: (Int, Int)? = (6000, 4000),
        words: [UInt16]
    ) -> [UInt8] {
        // Use TestTIFFBuilder's exact layout by padding a dummy MakerNote to determine its exact offset,
        // OR write IFD0 + ExifIFD directly with deterministic layout. Writing directly is 100% transparent.
        var ifd0Entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let make {
            ifd0Entries.append((0x010F, 2, UInt32(make.utf8.count + 1), Array(make.utf8) + [0]))
        }
        if let model {
            ifd0Entries.append((0x0110, 2, UInt32(model.utf8.count + 1), Array(model.utf8) + [0]))
        }
        if let orientation {
            var v: [UInt8] = []
            TestSupport.appendUInt16(orientation, to: &v, order: order)
            ifd0Entries.append((0x0112, 3, 1, v))
        }
        let exifIFDIndex = ifd0Entries.count
        ifd0Entries.append((0x8769, 4, 1, [0, 0, 0, 0]))

        var exifEntries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let imageExtent {
            var w: [UInt8] = []
            var h: [UInt8] = []
            TestSupport.appendUInt32(UInt32(imageExtent.0), to: &w, order: order)
            TestSupport.appendUInt32(UInt32(imageExtent.1), to: &h, order: order)
            exifEntries.append((0xA002, 4, 1, w))
            exifEntries.append((0xA003, 4, 1, h))
        }
        let mnByteLen = 2 + 12 + 4 + (words.count * 2 > 4 ? words.count * 2 : 0)
        let makerNoteIndex = exifEntries.count
        exifEntries.append((0x927C, 7, UInt32(mnByteLen), Array(repeating: 0, count: mnByteLen)))

        let ifd0Start = 8
        let ifd0TableSize = 2 + ifd0Entries.count * 12 + 4
        let exifStart = ifd0Start + ifd0TableSize
        let exifTableSize = 2 + exifEntries.count * 12 + 4
        var cursor = exifStart + exifTableSize

        // Patch IFD0 Exif pointer
        var exifPtrBytes: [UInt8] = []
        TestSupport.appendUInt32(UInt32(exifStart), to: &exifPtrBytes, order: order)
        ifd0Entries[exifIFDIndex].3 = exifPtrBytes

        var outOfLine: [UInt8] = []
        func buildTable(_ entries: [(UInt16, UInt16, UInt32, [UInt8])]) -> [UInt8] {
            var table: [UInt8] = []
            TestSupport.appendUInt16(UInt16(entries.count), to: &table, order: order)
            for (tag, type, count, val) in entries {
                TestSupport.appendUInt16(tag, to: &table, order: order)
                TestSupport.appendUInt16(type, to: &table, order: order)
                TestSupport.appendUInt32(count, to: &table, order: order)
                if val.count <= 4 {
                    table.append(contentsOf: val)
                    table.append(contentsOf: Array(repeating: 0, count: 4 - val.count))
                } else {
                    TestSupport.appendUInt32(UInt32(cursor), to: &table, order: order)
                    outOfLine.append(contentsOf: val)
                    cursor += val.count
                }
            }
            TestSupport.appendUInt32(0, to: &table, order: order)
            return table
        }

        // Calculate MakerNote offset after all prior out-of-line data is allocated:
        // MakerNote is the last entry in exifEntries, so its start will be `cursor` right before writing it.
        var mnOffset = exifStart + exifTableSize
        for e in ifd0Entries where e.3.count > 4 { mnOffset += e.3.count }
        for (idx, e) in exifEntries.enumerated() where idx < makerNoteIndex && e.3.count > 4 {
            mnOffset += e.3.count
        }
        exifEntries[makerNoteIndex].3 = canonMakerNoteDirectory(
            order: order,
            words: words,
            tiffBaseBeforeMakerNote: mnOffset
        )
        // Reset outOfLine & cursor cleanly so buildTable writes the real MakerNote at `mnOffset`.
        cursor = exifStart + exifTableSize
        outOfLine = []
        let finalIFD0 = buildTable(ifd0Entries)
        let finalExif = buildTable(exifEntries)

        var tiff: [UInt8] =
            order == .littleEndian ? [0x49, 0x49, 0x2A, 0x00] : [0x4D, 0x4D, 0x00, 0x2A]
        TestSupport.appendUInt32(8, to: &tiff, order: order)
        tiff.append(contentsOf: finalIFD0)
        tiff.append(contentsOf: finalExif)
        tiff.append(contentsOf: outOfLine)
        return tiff
    }

    static func canonCR3(
        order: TIFFByteOrder = .littleEndian,
        make: String? = "Canon",
        model: String? = "Canon EOS R5",
        software: String? = nil,
        orientation: UInt16? = 1,
        imageExtent: (Int, Int)? = (6000, 4000),
        afWords: [UInt16]?,
        omitCMT3: Bool = false
    ) -> Data {
        func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            var bytes: [UInt8] = []
            TestSupport.appendUInt32(UInt32(8 + payload.count), to: &bytes, order: .bigEndian)
            bytes.append(contentsOf: type.utf8)
            bytes.append(contentsOf: payload)
            return bytes
        }

        let ftyp = box("ftyp", Array("crx ".utf8) + [0, 0, 0, 1] + Array("crx isom".utf8))

        var cmt1Entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let make {
            cmt1Entries.append((0x010F, 2, UInt32(make.utf8.count + 1), Array(make.utf8) + [0]))
        }
        if let model {
            cmt1Entries.append((0x0110, 2, UInt32(model.utf8.count + 1), Array(model.utf8) + [0]))
        }
        if let software {
            cmt1Entries.append(
                (0x0131, 2, UInt32(software.utf8.count + 1), Array(software.utf8) + [0]))
        }
        if let orientation {
            var o: [UInt8] = []
            TestSupport.appendUInt16(orientation, to: &o, order: order)
            cmt1Entries.append((0x0112, 3, 1, o))
        }
        let cmt1Box = box("CMT1", singleIFDTIFF(order: order, entries: cmt1Entries))

        var cmt2Entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let imageExtent {
            var w: [UInt8] = []
            var h: [UInt8] = []
            TestSupport.appendUInt32(UInt32(imageExtent.0), to: &w, order: order)
            TestSupport.appendUInt32(UInt32(imageExtent.1), to: &h, order: order)
            cmt2Entries.append((0xA002, 4, 1, w))
            cmt2Entries.append((0xA003, 4, 1, h))
        }
        let cmt2Box = box("CMT2", singleIFDTIFF(order: order, entries: cmt2Entries))

        let cmt3Box: [UInt8]
        if omitCMT3 {
            cmt3Box = []
        } else if let afWords {
            let valueBytes = encodeWords(afWords, order: order)
            let tiff = singleIFDTIFF(
                order: order,
                entries: [(0x0026, 3, UInt32(afWords.count), valueBytes)]
            )
            cmt3Box = box("CMT3", tiff)
        } else {
            cmt3Box = box("CMT3", singleIFDTIFF(order: order, entries: []))
        }

        let canonUUID: [UInt8] = [
            0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0,
            0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48,
        ]
        let uuidBox = box("uuid", canonUUID + cmt1Box + cmt2Box + cmt3Box)
        let moov = box("moov", uuidBox)
        return Data(ftyp + moov)
    }

    static func nikonMakerNote(
        order: TIFFByteOrder = .littleEndian,
        version: String = "0300",
        contrastDetectByte: UInt8 = 1,
        focusMode: String? = "AF-S  ",
        afImageExtent: (UInt16, UInt16) = (6000, 4000),
        area: (x: UInt16, y: UInt16, width: UInt16, height: UInt16) = (1800, 1200, 300, 240),
        truncatedByteCount: Int? = nil,
        omitAFInfo2: Bool = false
    ) -> [UInt8] {
        var block: [UInt8] = []
        if !omitAFInfo2 {
            let areaOffset: Int
            let minLength: Int
            switch version {
            case "0300", "0301":
                areaOffset = 42
                minLength = 54
            case "0400", "0401", "0402":
                areaOffset = 62
                minLength = 74
            case "0100":
                areaOffset = 16
                minLength = contrastDetectByte == 1 ? 28 : 16
            default:
                areaOffset = 16
                minLength = 84
            }
            block = [UInt8](repeating: 0, count: minLength)
            let verBytes = Array(version.utf8)
            for i in 0..<min(4, verBytes.count) {
                block[i] = verBytes[i]
            }
            if version == "0100" {
                block[4] = contrastDetectByte
            }
            if minLength >= areaOffset + 12 {
                func writeWord(_ word: UInt16, at pos: Int) {
                    var tmp: [UInt8] = []
                    TestSupport.appendUInt16(word, to: &tmp, order: order)
                    block[pos] = tmp[0]
                    block[pos + 1] = tmp[1]
                }
                writeWord(afImageExtent.0, at: areaOffset)
                writeWord(afImageExtent.1, at: areaOffset + 2)
                writeWord(area.x, at: areaOffset + 4)
                writeWord(area.y, at: areaOffset + 6)
                writeWord(area.width, at: areaOffset + 8)
                writeWord(area.height, at: areaOffset + 10)
            }
            if let truncatedByteCount {
                block = Array(block.prefix(truncatedByteCount))
            }
        }

        var entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let focusMode {
            let ascii = Array(focusMode.utf8) + [0]
            entries.append((0x0007, 2, UInt32(ascii.count), ascii))
        }
        if !omitAFInfo2 {
            entries.append((0x00B7, 7, UInt32(block.count), block))
        }

        var prefix: [UInt8] = [0x4E, 0x69, 0x6B, 0x6F, 0x6E, 0x00, 0x02, 0x10, 0x00, 0x00]
        prefix.append(contentsOf: singleIFDTIFF(order: order, entries: entries))
        return prefix
    }

    static func fujifilmMakerNote(
        order: TIFFByteOrder = .littleEndian,
        focusMode: UInt16? = 0,
        focusPixel: (UInt16, UInt16)? = (1281, 1163),
        afAreaMode: UInt32? = 513,
        focusWarning: UInt16? = 0,
        directoryOffsetOverride: UInt32? = nil
    ) -> [UInt8] {
        var bytes = Array("FUJIFILM".utf8)
        // Directory offset is always little-endian 32-bit in Fujifilm MakerNote header.
        TestSupport.appendUInt32(directoryOffsetOverride ?? 12, to: &bytes, order: .littleEndian)
        var entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let focusMode {
            var v: [UInt8] = []
            TestSupport.appendUInt16(focusMode, to: &v, order: order)
            entries.append((0x1021, 3, 1, v))
        }
        if let focusPixel {
            var v: [UInt8] = []
            TestSupport.appendUInt16(focusPixel.0, to: &v, order: order)
            TestSupport.appendUInt16(focusPixel.1, to: &v, order: order)
            entries.append((0x1023, 3, 2, v))
        }
        if let afAreaMode {
            var v: [UInt8] = []
            TestSupport.appendUInt32(afAreaMode, to: &v, order: order)
            entries.append((0x102D, 4, 1, v))
        }
        if let focusWarning {
            var v: [UInt8] = []
            TestSupport.appendUInt16(focusWarning, to: &v, order: order)
            entries.append((0x1301, 3, 1, v))
        }

        let tableSize = 2 + entries.count * 12 + 4
        var cursor = 12 + tableSize
        var outOfLine: [UInt8] = []
        TestSupport.appendUInt16(UInt16(entries.count), to: &bytes, order: order)
        for (tag, type, count, val) in entries {
            TestSupport.appendUInt16(tag, to: &bytes, order: order)
            TestSupport.appendUInt16(type, to: &bytes, order: order)
            TestSupport.appendUInt32(count, to: &bytes, order: order)
            if val.count <= 4 {
                bytes.append(contentsOf: val)
                bytes.append(contentsOf: Array(repeating: 0, count: 4 - val.count))
            } else {
                TestSupport.appendUInt32(UInt32(cursor), to: &bytes, order: order)
                outOfLine.append(contentsOf: val)
                cursor += val.count
            }
        }
        TestSupport.appendUInt32(0, to: &bytes, order: order)
        bytes.append(contentsOf: outOfLine)
        return bytes
    }

    static func jpeg(exifTIFF: [UInt8], sofExtent: (width: UInt16, height: UInt16)? = nil) -> Data {
        var data: [UInt8] = [0xFF, 0xD8]
        let app1Payload = Array("Exif\0\0".utf8) + exifTIFF
        let app1Len = UInt16(2 + app1Payload.count)
        data.append(contentsOf: [0xFF, 0xE1, UInt8(app1Len >> 8), UInt8(app1Len & 0xFF)])
        data.append(contentsOf: app1Payload)

        if let sofExtent {
            // SOF0 marker: precision (1B) + height (2B BE) + width (2B BE) + components (1B + 3B)
            let sofPayload: [UInt8] = [
                8,
                UInt8(sofExtent.height >> 8), UInt8(sofExtent.height & 0xFF),
                UInt8(sofExtent.width >> 8), UInt8(sofExtent.width & 0xFF),
                1, 1, 0x11, 0,
            ]
            let sofLen = UInt16(2 + sofPayload.count)
            data.append(contentsOf: [0xFF, 0xC0, UInt8(sofLen >> 8), UInt8(sofLen & 0xFF)])
            data.append(contentsOf: sofPayload)
        }

        data.append(contentsOf: [0xFF, 0xD9])
        return Data(data)
    }

    static func heif(exifTIFF: [UInt8], width: Int = 80, height: Int = 60, irot: UInt8? = nil)
        -> Data
    {
        var builder = TestHEIFBuilder(exifTIFF: exifTIFF)
        builder.width = width
        builder.height = height
        builder.irotPayload = irot
        return Data(builder.build())
    }

    static func rw2(exifTIFF: [UInt8]) -> Data {
        let jpegBytes = Array(jpeg(exifTIFF: exifTIFF))
        var tiff = singleIFDTIFF(
            order: .littleEndian,
            entries: [
                (0x002E, 7, UInt32(jpegBytes.count), jpegBytes)
            ]
        )
        guard tiff.count >= 4 else { return Data(tiff) }
        tiff[2] = 0x55
        tiff[3] = 0x00
        return Data(tiff)
    }

    static func ricohStructuredBlock(
        header: [UInt8] = Array("RICOH\0II".utf8),
        afState: UInt16 = 2,
        formatVersion: UInt16 = 8194,
        declaredMaxBoxes: UInt16? = nil,
        actualSlotCount: Int = 25,
        slots: [(
            refW: UInt16, refH: UInt16, cx: UInt16, cy: UInt16, w: UInt16, h: UInt16, flags: UInt16
        )],
        focusSetting: UInt16? = 8,
        omitAFInfo: Bool = false,
        duplicateAFInfo: Bool = false,
        overrideAFBytes: [UInt8]? = nil
    ) -> [UInt8] {
        var entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let focusSetting {
            var val: [UInt8] = []
            TestSupport.appendUInt16(focusSetting, to: &val, order: .littleEndian)
            entries.append((0x000D, 3, 1, val))
        }

        let afBytes: [UInt8]
        if let overrideAFBytes {
            afBytes = overrideAFBytes
        } else {
            let maxBoxes = declaredMaxBoxes ?? UInt16(actualSlotCount)
            var words: [UInt16] = Array(repeating: 0, count: 7 + actualSlotCount * 7)
            let activeCount = UInt16(slots.filter { ($0.flags & 0x0004) != 0 }.count)
            words[0] = afState
            words[1] = formatVersion
            words[2] = maxBoxes
            words[3] = UInt16(slots.count)
            words[4] = activeCount
            for (index, slot) in slots.enumerated() where index < actualSlotCount {
                let base = 7 + index * 7
                words[base] = slot.refW
                words[base + 1] = slot.refH
                words[base + 2] = slot.cx
                words[base + 3] = slot.cy
                words[base + 4] = slot.w
                words[base + 5] = slot.h
                words[base + 6] = slot.flags
            }
            afBytes = encodeWords(words, order: .littleEndian)
        }

        if !omitAFInfo {
            entries.append((0x040C, 7, UInt32(afBytes.count), afBytes))
            if duplicateAFInfo {
                entries.append((0x040C, 7, UInt32(afBytes.count), afBytes))
            }
        }

        var block = header
        let tableSize = 2 + entries.count * 12 + 4
        var cursor = header.count + tableSize
        var outOfLine: [UInt8] = []
        TestSupport.appendUInt16(UInt16(entries.count), to: &block, order: .littleEndian)
        for (tag, type, count, value) in entries {
            TestSupport.appendUInt16(tag, to: &block, order: .littleEndian)
            TestSupport.appendUInt16(type, to: &block, order: .littleEndian)
            TestSupport.appendUInt32(count, to: &block, order: .littleEndian)
            if value.count <= 4 {
                block.append(contentsOf: value)
                block.append(contentsOf: Array(repeating: 0, count: 4 - value.count))
            } else {
                TestSupport.appendUInt32(UInt32(cursor), to: &block, order: .littleEndian)
                outOfLine.append(contentsOf: value)
                cursor += value.count
            }
        }
        TestSupport.appendUInt32(0, to: &block, order: .littleEndian)
        block.append(contentsOf: outOfLine)
        return block
    }

    static func ricohDNGWithPrivateData(
        make: String? = "RICOH IMAGING COMPANY, LTD.",
        model: String? = "RICOH GR IIIx",
        orientation: UInt16? = 1,
        imageExtent: (Int, Int)? = (6000, 4000),
        privateData: [UInt8]
    ) -> [UInt8] {
        var ifd0Entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let make {
            let bytes = Array(make.utf8) + [0]
            ifd0Entries.append((0x010F, 2, UInt32(bytes.count), bytes))
        }
        if let model {
            let bytes = Array(model.utf8) + [0]
            ifd0Entries.append((0x0110, 2, UInt32(bytes.count), bytes))
        }
        if let orientation {
            var val: [UInt8] = []
            TestSupport.appendUInt16(orientation, to: &val, order: .littleEndian)
            ifd0Entries.append((0x0112, 3, 1, val))
        }
        if let imageExtent {
            var exifEntries: [(UInt16, UInt16, UInt32, [UInt8])] = []
            var wVal: [UInt8] = []
            var hVal: [UInt8] = []
            TestSupport.appendUInt32(UInt32(imageExtent.0), to: &wVal, order: .littleEndian)
            TestSupport.appendUInt32(UInt32(imageExtent.1), to: &hVal, order: .littleEndian)
            exifEntries.append((0xA002, 4, 1, wVal))
            exifEntries.append((0xA003, 4, 1, hVal))
            ifd0Entries.append((0xC634, 7, UInt32(privateData.count), privateData))

            var exifBytes: [UInt8] = []
            TestSupport.appendUInt16(
                UInt16(exifEntries.count), to: &exifBytes, order: .littleEndian)
            for (tag, type, count, val) in exifEntries {
                TestSupport.appendUInt16(tag, to: &exifBytes, order: .littleEndian)
                TestSupport.appendUInt16(type, to: &exifBytes, order: .littleEndian)
                TestSupport.appendUInt32(count, to: &exifBytes, order: .littleEndian)
                exifBytes.append(contentsOf: val)
            }
            TestSupport.appendUInt32(0, to: &exifBytes, order: .littleEndian)

            var placeholderOffset = [UInt8](repeating: 0, count: 4)
            ifd0Entries.append((0x8769, 4, 1, placeholderOffset))
            let ifd0TableSize = 2 + ifd0Entries.count * 12 + 4
            var cursor = 8 + ifd0TableSize
            var outOfLine: [UInt8] = []
            var bytes: [UInt8] = [0x49, 0x49, 0x2A, 0x00]
            TestSupport.appendUInt32(8, to: &bytes, order: .littleEndian)
            TestSupport.appendUInt16(UInt16(ifd0Entries.count), to: &bytes, order: .littleEndian)
            for (tag, type, count, val) in ifd0Entries {
                TestSupport.appendUInt16(tag, to: &bytes, order: .littleEndian)
                TestSupport.appendUInt16(type, to: &bytes, order: .littleEndian)
                TestSupport.appendUInt32(count, to: &bytes, order: .littleEndian)
                if tag == 0x8769 {
                    TestSupport.appendUInt32(UInt32(cursor), to: &bytes, order: .littleEndian)
                    outOfLine.append(contentsOf: exifBytes)
                    cursor += exifBytes.count
                } else if val.count <= 4 {
                    bytes.append(contentsOf: val)
                    bytes.append(contentsOf: Array(repeating: 0, count: 4 - val.count))
                } else {
                    TestSupport.appendUInt32(UInt32(cursor), to: &bytes, order: .littleEndian)
                    outOfLine.append(contentsOf: val)
                    cursor += val.count
                }
            }
            _ = placeholderOffset.popLast()
            TestSupport.appendUInt32(0, to: &bytes, order: .littleEndian)
            bytes.append(contentsOf: outOfLine)
            return bytes
        }

        ifd0Entries.append((0xC634, 7, UInt32(privateData.count), privateData))
        return singleIFDTIFF(order: .littleEndian, entries: ifd0Entries)
    }

    static func enclosingTIFFMakerNoteTIFF(
        order: TIFFByteOrder = .littleEndian,
        make: String?,
        model: String?,
        orientation: UInt16? = 1,
        imageExtent: (Int, Int)? = nil,
        makerNoteHeader: [UInt8] = [],
        makerNoteEntries: [(tag: UInt16, type: UInt16, count: UInt32, value: [UInt8])],
        useMakerNoteRelativeOffsets: Bool = false,
        placeMakerNoteValuesOutsideMakerNoteRange: Bool = false
    ) -> [UInt8] {
        var ifd0Entries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let make {
            let bytes = Array(make.utf8) + [0]
            ifd0Entries.append((0x010F, 2, UInt32(bytes.count), bytes))
        }
        if let model {
            let bytes = Array(model.utf8) + [0]
            ifd0Entries.append((0x0110, 2, UInt32(bytes.count), bytes))
        }
        if let orientation {
            var val: [UInt8] = []
            TestSupport.appendUInt16(orientation, to: &val, order: order)
            ifd0Entries.append((0x0112, 3, 1, val))
        }
        ifd0Entries.append((0x8769, 4, 1, [0, 0, 0, 0]))

        var exifEntries: [(UInt16, UInt16, UInt32, [UInt8])] = []
        if let imageExtent {
            var wVal: [UInt8] = []
            var hVal: [UInt8] = []
            TestSupport.appendUInt32(UInt32(imageExtent.0), to: &wVal, order: order)
            TestSupport.appendUInt32(UInt32(imageExtent.1), to: &hVal, order: order)
            exifEntries.append((0xA002, 4, 1, wVal))
            exifEntries.append((0xA003, 4, 1, hVal))
        }
        let makerNoteIndex = exifEntries.count
        exifEntries.append((0x927C, 7, 0, []))

        let ifd0TableSize = 2 + ifd0Entries.count * 12 + 4
        let exifStart = 8 + ifd0TableSize
        let exifTableSize = 2 + exifEntries.count * 12 + 4

        var mnOffset = exifStart + exifTableSize
        for e in ifd0Entries where e.3.count > 4 { mnOffset += e.3.count }
        for (idx, e) in exifEntries.enumerated() where idx < makerNoteIndex && e.3.count > 4 {
            mnOffset += e.3.count
        }

        let mnTableSize = makerNoteHeader.count + 2 + makerNoteEntries.count * 12 + 4
        var mnOutOfLine: [UInt8] = []
        var mnBytes = makerNoteHeader
        TestSupport.appendUInt16(UInt16(makerNoteEntries.count), to: &mnBytes, order: order)

        let mnExternalStart = mnOffset + mnTableSize
        var valueCursor =
            useMakerNoteRelativeOffsets
            ? mnTableSize
            : (placeMakerNoteValuesOutsideMakerNoteRange ? mnExternalStart : mnOffset + mnTableSize)

        for entry in makerNoteEntries {
            TestSupport.appendUInt16(entry.tag, to: &mnBytes, order: order)
            TestSupport.appendUInt16(entry.type, to: &mnBytes, order: order)
            TestSupport.appendUInt32(entry.count, to: &mnBytes, order: order)
            if entry.value.count <= 4 {
                mnBytes.append(contentsOf: entry.value)
                mnBytes.append(contentsOf: Array(repeating: 0, count: 4 - entry.value.count))
            } else {
                TestSupport.appendUInt32(UInt32(valueCursor), to: &mnBytes, order: order)
                mnOutOfLine.append(contentsOf: entry.value)
                valueCursor += entry.value.count
            }
        }
        TestSupport.appendUInt32(0, to: &mnBytes, order: order)

        let declaredMakerNoteBytes: [UInt8]
        let trailingExternalBytes: [UInt8]
        if placeMakerNoteValuesOutsideMakerNoteRange {
            // Mirrors real Hasselblad .fff / .3FR files where Exif 0x927c byteCount wraps
            // only the IFD table while out-of-line values sit later in the outer TIFF.
            declaredMakerNoteBytes = mnBytes
            trailingExternalBytes = mnOutOfLine
        } else {
            mnBytes.append(contentsOf: mnOutOfLine)
            declaredMakerNoteBytes = mnBytes
            trailingExternalBytes = []
        }

        exifEntries[makerNoteIndex] = (
            0x927C, 7, UInt32(declaredMakerNoteBytes.count), declaredMakerNoteBytes
        )

        var cursor = exifStart + exifTableSize
        var outOfLine: [UInt8] = []
        func buildTable(_ entries: [(UInt16, UInt16, UInt32, [UInt8])]) -> [UInt8] {
            var table: [UInt8] = []
            TestSupport.appendUInt16(UInt16(entries.count), to: &table, order: order)
            for (tag, type, count, val) in entries {
                TestSupport.appendUInt16(tag, to: &table, order: order)
                TestSupport.appendUInt16(type, to: &table, order: order)
                TestSupport.appendUInt32(count, to: &table, order: order)
                if tag == 0x8769 {
                    TestSupport.appendUInt32(UInt32(exifStart), to: &table, order: order)
                } else if val.count <= 4 {
                    table.append(contentsOf: val)
                    table.append(contentsOf: Array(repeating: 0, count: 4 - val.count))
                } else {
                    TestSupport.appendUInt32(UInt32(cursor), to: &table, order: order)
                    outOfLine.append(contentsOf: val)
                    cursor += val.count
                }
            }
            TestSupport.appendUInt32(0, to: &table, order: order)
            return table
        }

        let finalIFD0 = buildTable(ifd0Entries)
        let finalExif = buildTable(exifEntries)

        var tiff: [UInt8] =
            order == .littleEndian ? [0x49, 0x49, 0x2A, 0x00] : [0x4D, 0x4D, 0x00, 0x2A]
        TestSupport.appendUInt32(8, to: &tiff, order: order)
        tiff.append(contentsOf: finalIFD0)
        tiff.append(contentsOf: finalExif)
        tiff.append(contentsOf: outOfLine)
        tiff.append(contentsOf: trailingExternalBytes)
        return tiff
    }
}
