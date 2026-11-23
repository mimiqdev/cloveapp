import Foundation

enum FujifilmReader {
    private static let focusModeTag: UInt16 = 0x1021
    private static let focusPixelTag: UInt16 = 0x1023
    private static let afAreaModeTag: UInt16 = 0x102D
    private static let focusWarningTag: UInt16 = 0x1301

    static func read(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        outerByteOrder: TIFFByteOrder,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> VendorReadOutcome? {
        guard makerNoteLength >= 12 else { return nil }
        let header: [UInt8]
        do {
            header = try reader.read(at: makerNoteOffset, count: 12)
        } catch {
            return nil
        }
        guard header.starts(with: Array("FUJIFILM".utf8)) else {
            return nil
        }
        let directoryOffset =
            Int(header[8]) | Int(header[9]) << 8 | Int(header[10]) << 16 | Int(header[11]) << 24
        guard directoryOffset >= 12, directoryOffset <= makerNoteLength else {
            var outcome = VendorReadOutcome(
                source: .fujifilmFocusPixel,
                geometry: .unavailable(.referenceExtentUnresolved(vendor: .fujifilm))
            )
            outcome.issues.append(
                MetadataIssue(
                    kind: .offsetOutOfBounds,
                    context: "Fujifilm MakerNote directory"
                )
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        var outcome = VendorReadOutcome(
            source: .fujifilmFocusPixel,
            geometry: .unavailable(.referenceExtentUnresolved(vendor: .fujifilm))
        )
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        let context = TIFFContext(
            reader: reader,
            base: makerNoteOffset,
            regionEnd: makerNoteEnd,
            byteOrder: outerByteOrder
        )
        var visited: Set<Int> = []
        let index: TIFFEntryIndex
        do {
            index = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: makerNoteOffset + directoryOffset,
                context: context,
                limits: limits,
                visited: &visited,
                depth: 1
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Fujifilm MakerNote directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        if index.duplicateTags.contains(focusPixelTag) {
            outcome.issues.append(
                MetadataIssue(kind: .duplicateTag, context: "Fujifilm 0x1023")
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        var focusPixel: (UInt16, UInt16)?
        if let entry = index.uniqueEntry(tag: focusPixelTag) {
            guard entry.type == 3, entry.count == 2 else {
                outcome.issues.append(
                    MetadataIssue(
                        kind: .unexpectedFieldShape,
                        context: "Fujifilm 0x1023",
                        detail:
                            "Expected TIFF SHORT count 2; found type \(entry.type) count \(entry.count)."
                    )
                )
                outcome.malformedFocusPath = true
                return outcome
            }
            do {
                if let values = try context.readUnsignedValues(of: entry),
                    values.count == 2,
                    let x = UInt16(exactly: values[0]),
                    let y = UInt16(exactly: values[1])
                {
                    focusPixel = (x, y)
                    outcome.records.append(
                        VendorRawRecord(
                            tag: UInt32(focusPixelTag),
                            name: "Focus pixel word pair",
                            fieldType: entry.type,
                            values: .unsignedWords(values)
                        )
                    )
                } else {
                    outcome.issues.append(
                        MetadataIssue(kind: .unexpectedFieldShape, context: "Fujifilm 0x1023")
                    )
                    outcome.malformedFocusPath = true
                    return outcome
                }
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Fujifilm 0x1023")
                )
                outcome.malformedFocusPath = true
                return outcome
            } catch {
                outcome.malformedFocusPath = true
                return outcome
            }
        }

        var focusMode: UInt64?
        if index.duplicateTags.contains(focusModeTag) {
            outcome.issues.append(
                MetadataIssue(kind: .duplicateTag, context: "Fujifilm 0x1021")
            )
        } else if let entry = index.uniqueEntry(tag: focusModeTag) {
            if entry.type == 3, entry.count == 1,
                let values = try? context.readUnsignedValues(of: entry),
                let value = values.first
            {
                focusMode = value
                outcome.records.append(
                    VendorRawRecord(
                        tag: UInt32(focusModeTag),
                        name: "Vendor tag 0x1021 value",
                        fieldType: entry.type,
                        values: .unsignedWords(values)
                    )
                )
            } else {
                outcome.issues.append(
                    MetadataIssue(kind: .unexpectedFieldShape, context: "Fujifilm 0x1021")
                )
            }
        }

        VendorReaders.appendSimpleWordRecord(
            tag: afAreaModeTag,
            expectedType: 4,
            expectedCount: 1,
            name: "Vendor tag 0x102d value",
            index: index,
            context: context,
            outcome: &outcome
        )
        VendorReaders.appendSimpleWordRecord(
            tag: focusWarningTag,
            expectedType: 3,
            expectedCount: 1,
            name: "Vendor tag 0x1301 value",
            index: index,
            context: context,
            outcome: &outcome
        )

        if outcome.records.isEmpty {
            outcome.issues.append(
                MetadataIssue(kind: .missingFocusMetadata, context: "Fujifilm MakerNote")
            )
            return outcome
        }

        if let focusMode {
            if focusMode == 1 {
                // Fujifilm FocusMode 1 indicates manual focus.
                outcome.isVerifiedScope = true
                outcome.referenceExtent = imageExtent
                outcome.geometry = .unavailable(.noRegionRecorded(vendor: .fujifilm))
                outcome.uncertainties.append(.focusSuccessNotEstablished)
                return outcome
            }
            if focusMode != 0 {
                outcome.geometry = .unavailable(.vendorSemanticsUnverified(vendor: .fujifilm))
                return outcome
            }
        }

        guard let focusPixel else {
            outcome.isVerifiedScope = true
            outcome.referenceExtent = imageExtent
            outcome.geometry = .unavailable(.noLocationRecorded)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        guard let extent = imageExtent else {
            outcome.geometry = .unavailable(.referenceExtentUnresolved(vendor: .fujifilm))
            return outcome
        }

        outcome.isVerifiedScope = true
        outcome.referenceExtent = extent

        // Empirically verified on X-S10, X-S20, X-Pro3, X-T20, X100F, and X100VI:
        // 0x1023 FocusPixel is top-left origin in the embedded JPEG / Exif pixel extent.
        let center = ContinuousPoint(x: Double(focusPixel.0), y: Double(focusPixel.1))
        guard
            let location = FocusLocationGeometry(
                space: .storedReference,
                extent: extent,
                center: center
            )
        else {
            outcome.geometry = .unavailable(.centerOutsideReference)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        outcome.geometry = .location(location)
        outcome.uncertainties.append(contentsOf: [
            .focusSuccessNotEstablished,
            .coordinateIndexConventionUnverified,
            .continuousCoordinateApproximation,
        ])
        return outcome
    }
}
