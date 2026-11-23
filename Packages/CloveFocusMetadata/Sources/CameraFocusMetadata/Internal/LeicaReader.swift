import Foundation

/// Reads Leica MakerNote structures (`LEICA\0` variants and Panasonic-derived `LEICA CAMERA AG\0\0\0`)
/// as honest unverified raw observations.
enum LeicaReader {
    private static let panasonicDerivedPrefix: [UInt8] = Array("LEICA CAMERA AG\0\0\0".utf8)
    private static let nativePrefix: [UInt8] = Array("LEICA\0".utf8)

    private static let panasonicAFPositionTag: UInt16 = 0x004D
    private static let panasonicFocusModeTag: UInt16 = 0x0007
    private static let nativeOpaqueSummaryTags: [UInt16] = [0x04FF, 0x05FF]
    private static let nativeAFAdjacentWordTags: [UInt16] = [
        0x0304, 0x0346, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
    ]

    /// Reads a Leica MakerNote when `headerBytes` begins with `LEICA CAMERA AG\0\0\0` or `LEICA\0`.
    static func readMakerNote(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        headerBytes: [UInt8],
        outerContext: TIFFContext,
        limits: FocusMetadataReader.Limits
    ) -> (flavor: MakerNoteFlavor, outcome: VendorReadOutcome)? {
        if headerBytes.starts(with: panasonicDerivedPrefix) {
            let outcome = readPanasonicDerivedMakerNote(
                reader: reader,
                makerNoteOffset: makerNoteOffset,
                makerNoteLength: makerNoteLength,
                outerContext: outerContext,
                limits: limits
            )
            return (.leicaPanasonicDerived, outcome)
        }

        if headerBytes.starts(with: nativePrefix) {
            let outcome = readNativeMakerNote(
                reader: reader,
                makerNoteOffset: makerNoteOffset,
                makerNoteLength: makerNoteLength,
                outerContext: outerContext,
                limits: limits
            )
            return (.leica, outcome)
        }

        return nil
    }

    private static func readPanasonicDerivedMakerNote(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        outerContext: TIFFContext,
        limits: FocusMetadataReader.Limits
    ) -> VendorReadOutcome {
        var outcome = VendorReadOutcome(
            source: .leicaMakerNote,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .leica))
        )

        let directoryOffset = makerNoteOffset + panasonicDerivedPrefix.count
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        guard makerNoteLength >= panasonicDerivedPrefix.count + 2,
            makerNoteOffset <= reader.length - makerNoteLength
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .malformedMakerNote,
                    context: "Leica Panasonic-derived MakerNote"
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        let directory: TIFFEntryIndex
        do {
            var visited = Set<Int>()
            directory = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: directoryOffset,
                context: outerContext,
                limits: limits,
                visited: &visited,
                depth: 0,
                tableEnd: makerNoteEnd
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Leica Panasonic-derived MakerNote")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.issues.append(
                MetadataIssue(kind: .invalidIFD, context: "Leica Panasonic-derived MakerNote")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        VendorReaders.appendSimpleWordRecord(
            tag: panasonicFocusModeTag,
            expectedType: 3,
            expectedCount: 1,
            name: "Leica Panasonic-derived 0x0007 focus mode",
            index: directory,
            context: outerContext,
            outcome: &outcome
        )

        if directory.duplicateTags.contains(panasonicAFPositionTag) {
            outcome.issues.append(
                MetadataIssue(kind: .duplicateTag, context: "Leica Panasonic-derived 0x004d")
            )
            outcome.malformedFocusPath = true
        } else if let afEntry = directory.uniqueEntry(tag: panasonicAFPositionTag) {
            outcome.source = .leicaPanasonicAFPosition
            do {
                if let rationals = try outerContext.readRationals(of: afEntry),
                    rationals.count == 2
                {
                    outcome.records.append(
                        VendorRawRecord(
                            tag: UInt32(panasonicAFPositionTag),
                            name: "Recorded AF position rational pair",
                            fieldType: afEntry.type,
                            values: .rationals(rationals)
                        )
                    )
                    outcome.geometry = .unavailable(.originConventionUnverified(vendor: .leica))
                } else {
                    outcome.issues.append(
                        MetadataIssue(
                            kind: .unexpectedFieldShape,
                            context: "Leica Panasonic-derived 0x004d"
                        )
                    )
                    outcome.malformedFocusPath = true
                }
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Leica Panasonic-derived 0x004d")
                )
                outcome.malformedFocusPath = true
            } catch {
                outcome.malformedFocusPath = true
            }
        }

        if outcome.records.isEmpty && !outcome.malformedFocusPath {
            outcome.records.append(
                VendorRawRecord(
                    tag: nil,
                    name: "Leica Panasonic-derived MakerNote entry count",
                    fieldType: 3,
                    values: .unsignedWords([UInt64(directory.entries.count)])
                )
            )
        }

        outcome.uncertainties.append(.focusSuccessNotEstablished)
        return outcome
    }

    private static func readNativeMakerNote(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        outerContext: TIFFContext,
        limits: FocusMetadataReader.Limits
    ) -> VendorReadOutcome {
        var outcome = VendorReadOutcome(
            source: .leicaMakerNote,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .leica))
        )

        // Header is 6-byte "LEICA\0" + 2 variant bytes (e.g. 02 00, 05 00, 08 00, 09 00, 0a 00).
        let headerSize = nativePrefix.count + 2
        let directoryOffset = makerNoteOffset + headerSize
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        guard makerNoteLength >= headerSize + 2,
            makerNoteOffset <= reader.length - makerNoteLength
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .malformedMakerNote,
                    context: "Leica MakerNote directory",
                    detail: "The MakerNote is too short to contain an IFD entry count."
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        let header: [UInt8]
        do {
            header = try reader.read(at: makerNoteOffset, count: headerSize)
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Leica MakerNote header")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        let variantByte0 = header[6]
        let variantByte1 = header[7]

        let directory: TIFFEntryIndex
        do {
            var visited = Set<Int>()
            directory = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: directoryOffset,
                context: outerContext,
                limits: limits,
                visited: &visited,
                depth: 0,
                tableEnd: makerNoteEnd
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Leica MakerNote directory")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.issues.append(
                MetadataIssue(kind: .invalidIFD, context: "Leica MakerNote directory")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        // Leica X2 (variant 05 00) writes out-of-line value offsets relative to makerNoteOffset,
        // while M/Q/Q2/SL/SL2/SL3/CL variants write offsets relative to outerContext.base.
        let valueContext = resolveValueContext(
            variant: (variantByte0, variantByte1),
            directory: directory,
            reader: reader,
            makerNoteOffset: makerNoteOffset,
            makerNoteLength: makerNoteLength,
            outerContext: outerContext
        )

        outcome.records.append(
            VendorRawRecord(
                tag: nil,
                name: "Leica MakerNote header variant",
                fieldType: 1,
                values: .unsignedWords([UInt64(variantByte0), UInt64(variantByte1)])
            )
        )

        for tag in nativeAFAdjacentWordTags {
            let tagHex = String(tag, radix: 16)
            if directory.duplicateTags.contains(tag) {
                outcome.issues.append(
                    MetadataIssue(kind: .duplicateTag, context: "Leica tag 0x\(tagHex)")
                )
                continue
            }
            guard let entry = directory.uniqueEntry(tag: tag),
                let byteCount = entry.declaredByteCount,
                byteCount <= 64
            else {
                continue
            }
            do {
                if let words = try valueContext.readUnsignedValues(of: entry) {
                    outcome.records.append(
                        VendorRawRecord(
                            tag: UInt32(tag),
                            name: "Leica 0x\(tagHex) observation words",
                            fieldType: entry.type,
                            values: .unsignedWords(words)
                        )
                    )
                }
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Leica tag 0x\(tagHex)")
                )
            } catch {}
        }

        for tag in nativeOpaqueSummaryTags {
            let tagHex = String(tag, radix: 16)
            if directory.duplicateTags.contains(tag) {
                outcome.issues.append(
                    MetadataIssue(kind: .duplicateTag, context: "Leica tag 0x\(tagHex)")
                )
                continue
            }
            guard let entry = directory.uniqueEntry(tag: tag),
                let byteCount = entry.declaredByteCount
            else {
                continue
            }
            outcome.records.append(
                VendorRawRecord(
                    tag: UInt32(tag),
                    name: "Leica 0x\(tagHex) opaque block size",
                    fieldType: entry.type,
                    values: .unsignedWords([UInt64(byteCount)])
                )
            )
        }

        outcome.uncertainties.append(.focusSuccessNotEstablished)
        return outcome
    }

    private static func resolveValueContext(
        variant: (UInt8, UInt8),
        directory: TIFFEntryIndex,
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        outerContext: TIFFContext
    ) -> TIFFContext {
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        let makerNoteContext = TIFFContext(
            reader: reader,
            base: makerNoteOffset,
            regionEnd: makerNoteEnd,
            byteOrder: outerContext.byteOrder
        )
        if variant.0 == 0x05 && variant.1 == 0x00 {
            return makerNoteContext
        }
        // Fallback detector in case another firmware variant uses MakerNote-relative out-of-line offsets.
        for entry in directory.entries {
            guard let byteCount = entry.declaredByteCount, byteCount > 4 else { continue }
            if outerContext.base == 0,
                let outerOffset = try? outerContext.valueOffset(for: entry),
                outerOffset < makerNoteOffset,
                let mnOffset = try? makerNoteContext.valueOffset(for: entry),
                byteCount <= makerNoteEnd - mnOffset
            {
                return makerNoteContext
            }
        }
        return outerContext
    }
}
