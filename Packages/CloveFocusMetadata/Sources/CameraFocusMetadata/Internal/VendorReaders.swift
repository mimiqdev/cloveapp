import Foundation

struct VendorReadOutcome {
    var records: [VendorRawRecord] = []
    var issues: [MetadataIssue] = []
    var uncertainties: [Uncertainty] = []
    var malformedFocusPath = false
    var isVerifiedScope = false
    var source: FocusSource
    var geometry: FocusGeometry
    var referenceExtent: PixelExtent? = nil
}

enum VendorReaders {
    static func readPanasonic(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        outerContext: TIFFContext,
        limits: FocusMetadataReader.Limits
    ) -> VendorReadOutcome? {
        guard makerNoteLength >= 12 else { return nil }
        let prefix: [UInt8]
        do {
            prefix = try reader.read(at: makerNoteOffset, count: 12)
        } catch {
            return nil
        }
        guard prefix.starts(with: Array("Panasonic".utf8)) else {
            return nil
        }

        var outcome = VendorReadOutcome(
            source: .panasonicAFPosition,
            geometry: .unavailable(.originConventionUnverified(vendor: .panasonic))
        )
        var visited: Set<Int> = []
        let index: TIFFEntryIndex
        do {
            index = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: makerNoteOffset + 12,
                context: outerContext,
                limits: limits,
                visited: &visited,
                depth: 1,
                tableEnd: makerNoteOffset + makerNoteLength
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Panasonic MakerNote directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        if let entry = index.uniqueEntry(tag: 0x004D), entry.type == 5, entry.count == 2 {
            do {
                if let rationals = try outerContext.readRationals(of: entry) {
                    outcome.records.append(
                        VendorRawRecord(
                            tag: 0x004D,
                            name: "Recorded AF position rational pair",
                            fieldType: entry.type,
                            values: .rationals(rationals)
                        )
                    )
                }
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Panasonic 0x004d")
                )
                outcome.malformedFocusPath = true
            } catch {}
        }
        appendSimpleWordRecord(
            tag: 0x0007,
            expectedType: 3,
            expectedCount: 1,
            name: "Recorded focus mode",
            index: index,
            context: outerContext,
            outcome: &outcome
        )
        if let entry = index.uniqueEntry(tag: 0x000F), entry.type == 1, entry.count == 2 {
            do {
                outcome.records.append(
                    VendorRawRecord(
                        tag: 0x000F,
                        name: "Recorded focus setting bytes",
                        fieldType: entry.type,
                        values: .unsignedBytes(try outerContext.readValue(of: entry))
                    )
                )
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Panasonic 0x000f")
                )
            } catch {}
        }
        appendSimpleWordRecord(
            tag: 0x004B,
            expectedType: 4,
            expectedCount: 1,
            name: "Vendor tag 0x004b value",
            index: index,
            context: outerContext,
            outcome: &outcome
        )
        appendSimpleWordRecord(
            tag: 0x004C,
            expectedType: 4,
            expectedCount: 1,
            name: "Vendor tag 0x004c value",
            index: index,
            context: outerContext,
            outcome: &outcome
        )

        if outcome.records.isEmpty {
            outcome.issues.append(
                MetadataIssue(
                    kind: .missingFocusMetadata,
                    context: "Panasonic MakerNote"
                )
            )
        }
        return outcome
    }

    static func readOlympus(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        limits: FocusMetadataReader.Limits
    ) -> VendorReadOutcome? {
        guard makerNoteLength >= 14 else { return nil }
        let header: [UInt8]
        do {
            header = try reader.read(at: makerNoteOffset, count: 14)
        } catch {
            return nil
        }
        guard header.starts(with: Array("OLYMPUS".utf8)), header[7] == 0 else {
            return nil
        }
        let byteOrder: TIFFByteOrder
        switch (header[8], header[9]) {
        case (0x49, 0x49):
            byteOrder = .littleEndian
        case (0x4D, 0x4D):
            byteOrder = .bigEndian
        default:
            return nil
        }

        var outcome = VendorReadOutcome(
            source: .olympusCameraSettings,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .olympus))
        )
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        let context = TIFFContext(
            reader: reader,
            base: makerNoteOffset,
            regionEnd: makerNoteEnd,
            byteOrder: byteOrder
        )
        var visited: Set<Int> = []
        let index: TIFFEntryIndex
        do {
            index = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: makerNoteOffset + 12,
                context: context,
                limits: limits,
                visited: &visited,
                depth: 1
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Olympus MakerNote directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        guard let settingsEntry = index.uniqueEntry(tag: 0x2020),
            settingsEntry.type == 13, settingsEntry.count == 1
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .missingFocusMetadata,
                    context: "Olympus CameraSettings"
                )
            )
            return outcome
        }

        let settingsOffset: UInt32
        switch byteOrder {
        case .littleEndian:
            settingsOffset =
                UInt32(settingsEntry.valueField[0])
                | (UInt32(settingsEntry.valueField[1]) << 8)
                | (UInt32(settingsEntry.valueField[2]) << 16)
                | (UInt32(settingsEntry.valueField[3]) << 24)
        case .bigEndian:
            settingsOffset =
                (UInt32(settingsEntry.valueField[0]) << 24)
                | (UInt32(settingsEntry.valueField[1]) << 16)
                | (UInt32(settingsEntry.valueField[2]) << 8)
                | UInt32(settingsEntry.valueField[3])
        }

        let settingsIndex: TIFFEntryIndex
        do {
            settingsIndex = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: makerNoteOffset + Int(settingsOffset),
                context: context,
                limits: limits,
                visited: &visited,
                depth: 2
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Olympus CameraSettings directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        appendWordsRecord(
            tag: 0x0301,
            expectedType: 3,
            expectedCount: 2,
            name: "AF processing words",
            index: settingsIndex,
            context: context,
            outcome: &outcome
        )
        appendWordsRecord(
            tag: 0x0302,
            expectedType: 3,
            expectedCount: 2,
            name: "AF mode words",
            index: settingsIndex,
            context: context,
            outcome: &outcome
        )
        appendWordsRecord(
            tag: 0x0303,
            expectedType: 3,
            expectedCount: 1,
            name: "Vendor tag 0x0303 value",
            index: settingsIndex,
            context: context,
            outcome: &outcome
        )
        appendWordsRecord(
            tag: 0x0304,
            expectedType: 4,
            expectedCount: 64,
            name: "Vendor tag 0x0304 values",
            index: settingsIndex,
            context: context,
            outcome: &outcome
        )
        if let entry = settingsIndex.uniqueEntry(tag: 0x0305), entry.type == 10,
            entry.count == 5
        {
            do {
                if let rationals = try context.readRationals(of: entry) {
                    outcome.records.append(
                        VendorRawRecord(
                            tag: 0x0305,
                            name: "Vendor tag 0x0305 values",
                            fieldType: entry.type,
                            values: .rationals(rationals)
                        )
                    )
                }
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Olympus 0x0305")
                )
                outcome.malformedFocusPath = true
            } catch {}
        }

        let areaRecord = outcome.records.first { $0.tag == 0x0304 }
        let rationalRecord = outcome.records.first { $0.tag == 0x0305 }
        if let areaRecord, let rationalRecord {
            let areaIsZero: Bool
            if case .unsignedWords(let words) = areaRecord.values {
                areaIsZero = words.allSatisfy { $0 == 0 }
            } else {
                areaIsZero = false
            }
            let rationalsAreZero: Bool
            if case .rationals(let rationals) = rationalRecord.values {
                rationalsAreZero = rationals.allSatisfy {
                    $0.numerator == 0 && $0.denominator == 0
                }
            } else {
                rationalsAreZero = false
            }
            if areaIsZero && rationalsAreZero {
                outcome.geometry = .unavailable(.noRegionRecorded(vendor: .olympus))
            }
        }

        if outcome.records.isEmpty {
            outcome.issues.append(
                MetadataIssue(
                    kind: .missingFocusMetadata,
                    context: "Olympus CameraSettings"
                )
            )
        }
        return outcome
    }

    static func readPentax(
        reader: BoundedReader,
        payloadOffset: Int,
        payloadLength: Int,
        limits: FocusMetadataReader.Limits
    ) -> VendorReadOutcome? {
        guard payloadLength >= 12 else { return nil }
        let header: [UInt8]
        do {
            header = try reader.read(at: payloadOffset, count: 12)
        } catch {
            return nil
        }
        guard header.starts(with: Array("PENTAX".utf8)), header[7] == 0 else {
            return nil
        }
        let byteOrder: TIFFByteOrder
        switch (header[8], header[9]) {
        case (0x49, 0x49):
            byteOrder = .littleEndian
        case (0x4D, 0x4D):
            byteOrder = .bigEndian
        default:
            return nil
        }

        var outcome = VendorReadOutcome(
            source: .pentaxFocusSelection,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .pentax))
        )
        let payloadEnd = payloadOffset + payloadLength
        let context = TIFFContext(
            reader: reader,
            base: payloadOffset,
            regionEnd: payloadEnd,
            byteOrder: byteOrder
        )
        var visited: Set<Int> = []
        let index: TIFFEntryIndex
        do {
            index = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: payloadOffset + 10,
                context: context,
                limits: limits,
                visited: &visited,
                depth: 1
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Pentax vendor directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        appendWordsRecord(
            tag: 0x000D,
            expectedType: 3,
            expectedCount: 1,
            name: "Recorded focus mode",
            index: index,
            context: context,
            outcome: &outcome
        )
        appendWordsRecord(
            tag: 0x000E,
            expectedType: 3,
            expectedCount: 2,
            name: "Recorded focus point selection",
            index: index,
            context: context,
            outcome: &outcome
        )
        if let entry = index.uniqueEntry(tag: 0x021F), entry.type == 7, entry.count == 19 {
            do {
                outcome.records.append(
                    VendorRawRecord(
                        tag: 0x021F,
                        name: "Vendor tag 0x021f bytes",
                        fieldType: entry.type,
                        values: .unsignedBytes(try context.readValue(of: entry))
                    )
                )
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Pentax 0x021f")
                )
                outcome.malformedFocusPath = true
            } catch {}
        }

        if outcome.records.isEmpty {
            outcome.issues.append(
                MetadataIssue(
                    kind: .missingFocusMetadata,
                    context: "Pentax vendor payload"
                )
            )
        }
        return outcome
    }

    static func appendSimpleWordRecord(
        tag: UInt16,
        expectedType: UInt16,
        expectedCount: UInt32,
        name: String,
        index: TIFFEntryIndex,
        context: TIFFContext,
        outcome: inout VendorReadOutcome
    ) {
        guard let entry = index.uniqueEntry(tag: tag) else { return }
        guard entry.type == expectedType, entry.count == expectedCount else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unexpectedFieldShape,
                    context: "Vendor tag 0x\(String(tag, radix: 16))"
                )
            )
            return
        }
        do {
            if let values = try context.readUnsignedValues(of: entry) {
                outcome.records.append(
                    VendorRawRecord(
                        tag: UInt32(tag),
                        name: name,
                        fieldType: entry.type,
                        values: .unsignedWords(values)
                    )
                )
            }
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Vendor tag 0x\(String(tag, radix: 16))")
            )
        } catch {}
    }

    private static func appendWordsRecord(
        tag: UInt16,
        expectedType: UInt16,
        expectedCount: UInt32,
        name: String,
        index: TIFFEntryIndex,
        context: TIFFContext,
        outcome: inout VendorReadOutcome
    ) {
        appendSimpleWordRecord(
            tag: tag,
            expectedType: expectedType,
            expectedCount: expectedCount,
            name: name,
            index: index,
            context: context,
            outcome: &outcome
        )
    }
}
