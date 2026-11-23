import Foundation

enum CanonReader {
    private static let afInfoTag: UInt16 = 0x0026

    static func readCMT3(
        reader: BoundedReader,
        tiffOffset: Int,
        tiffEnd: Int,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> VendorReadOutcome? {
        let header: TIFFHeaderInfo
        do {
            header = try TIFFHeaderParser.read(reader: reader, at: tiffOffset, regionEnd: tiffEnd)
        } catch {
            return nil
        }
        let context = TIFFContext(
            reader: reader,
            base: tiffOffset,
            regionEnd: tiffEnd,
            byteOrder: header.byteOrder
        )
        var visited: Set<Int> = []
        let index: TIFFEntryIndex
        do {
            let absolute = try context.absolute(relativeOffset: header.firstIFDOffset)
            index = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: absolute,
                context: context,
                limits: limits,
                visited: &visited,
                depth: 1
            )
        } catch {
            return nil
        }

        return readAFInformation(
            index: index,
            context: context,
            source: .canonCR3AFInformation,
            contextLabel: "Canon CMT3 0x0026",
            limits: limits,
            imageExtent: imageExtent
        )
    }

    static func readMakerNote(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        context: TIFFContext,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> VendorReadOutcome {
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        guard makerNoteOffset >= 0, makerNoteOffset + 2 <= makerNoteEnd else {
            var outcome = VendorReadOutcome(
                source: .canonMakerNoteAFInformation,
                geometry: .unavailable(.vendorSemanticsUnverified(vendor: .canon))
            )
            outcome.issues.append(
                MetadataIssue(
                    kind: .malformedMakerNote,
                    context: "Canon MakerNote directory",
                    detail: "The MakerNote is too short to contain a directory count."
                )
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        var visited: Set<Int> = []
        let index: TIFFEntryIndex
        do {
            index = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: makerNoteOffset,
                context: context,
                limits: limits,
                visited: &visited,
                depth: 1,
                tableEnd: makerNoteEnd
            )
        } catch let failure as ParseFailure {
            var outcome = VendorReadOutcome(
                source: .canonMakerNoteAFInformation,
                geometry: .unavailable(.vendorSemanticsUnverified(vendor: .canon))
            )
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Canon MakerNote directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            var outcome = VendorReadOutcome(
                source: .canonMakerNoteAFInformation,
                geometry: .unavailable(.vendorSemanticsUnverified(vendor: .canon))
            )
            outcome.issues.append(
                MetadataIssue(kind: .malformedMakerNote, context: "Canon MakerNote directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        return readAFInformation(
            index: index,
            context: context,
            source: .canonMakerNoteAFInformation,
            contextLabel: "Canon MakerNote 0x0026",
            limits: limits,
            imageExtent: imageExtent
        )
    }

    static func readAFInformation(
        index: TIFFEntryIndex,
        context: TIFFContext,
        source: FocusSource,
        contextLabel: String,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> VendorReadOutcome {
        var outcome = VendorReadOutcome(
            source: source,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .canon))
        )

        if index.duplicateTags.contains(afInfoTag) {
            outcome.issues.append(MetadataIssue(kind: .duplicateTag, context: contextLabel))
            outcome.malformedFocusPath = true
            return outcome
        }

        guard let entry = index.uniqueEntry(tag: afInfoTag) else {
            outcome.issues.append(
                MetadataIssue(kind: .missingFocusMetadata, context: contextLabel)
            )
            return outcome
        }

        guard entry.type == 3, entry.count >= 8,
            let byteCount = entry.declaredByteCount,
            byteCount <= limits.maximumValueBytes
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unexpectedFieldShape,
                    context: contextLabel,
                    detail:
                        "Expected TIFF SHORT count >= 8; found type \(entry.type) count \(entry.count)."
                )
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        let words: [UInt16]
        let rawValues: [UInt64]
        do {
            guard let values = try context.readUnsignedValues(of: entry), values.count >= 8 else {
                outcome.issues.append(
                    MetadataIssue(kind: .unexpectedFieldShape, context: contextLabel)
                )
                outcome.malformedFocusPath = true
                return outcome
            }
            rawValues = values
            var parsed: [UInt16] = []
            parsed.reserveCapacity(values.count)
            for value in values {
                guard let word = UInt16(exactly: value) else {
                    outcome.issues.append(
                        MetadataIssue(kind: .unexpectedFieldShape, context: contextLabel)
                    )
                    outcome.malformedFocusPath = true
                    return outcome
                }
                parsed.append(word)
            }
            words = parsed
        } catch let failure as ParseFailure {
            outcome.issues.append(MetadataIssue(failure: failure, context: contextLabel))
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        outcome.records.append(
            VendorRawRecord(
                tag: UInt32(afInfoTag),
                name: "AF information block prefix words",
                fieldType: entry.type,
                values: .unsignedWords(Array(rawValues.prefix(8)))
            )
        )
        if let final = rawValues.last {
            outcome.records.append(
                VendorRawRecord(
                    tag: UInt32(afInfoTag),
                    name: "AF information block final word",
                    fieldType: entry.type,
                    values: .unsignedWords([final])
                )
            )
        }

        let declaredBytes = Int(words[0])
        let actualBytes = words.count * 2
        if declaredBytes > actualBytes {
            outcome.issues.append(
                MetadataIssue(
                    kind: .truncatedData,
                    context: contextLabel,
                    detail:
                        "Declared AF block byte count (\(declaredBytes)) exceeds payload size (\(actualBytes))."
                )
            )
            outcome.malformedFocusPath = true
            return outcome
        }
        if declaredBytes != actualBytes {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unsupportedVendorFocusLayout,
                    context: contextLabel,
                    detail:
                        "Declared AF block byte count (\(declaredBytes)) does not match AFInfo2/AFInfo3 payload (\(actualBytes))."
                )
            )
            return outcome
        }

        let numAFPoints = Int(words[2])
        let validAFPoints = Int(words[3])
        let afImageWidth = Int(words[6])
        let afImageHeight = Int(words[7])

        guard numAFPoints > 0, validAFPoints <= numAFPoints else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unexpectedFieldShape,
                    context: contextLabel,
                    detail: "Invalid AF point counts (\(validAFPoints) of \(numAFPoints))."
                )
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        let maskWords = (numAFPoints + 15) / 16
        let (fourPoints, overflow1) = numAFPoints.multipliedReportingOverflow(by: 4)
        let (inFocusOffset, overflow2) = fourPoints.addingReportingOverflow(8)
        let (minWords, overflow3) = inFocusOffset.addingReportingOverflow(maskWords)
        guard !overflow1, !overflow2, !overflow3 else {
            outcome.issues.append(
                MetadataIssue(kind: .arithmeticOverflow, context: contextLabel)
            )
            outcome.malformedFocusPath = true
            return outcome
        }
        guard minWords <= words.count else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .truncatedData,
                    context: contextLabel,
                    detail: "Canon AF block is shorter than required for \(numAFPoints) points."
                )
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        outcome.isVerifiedScope = true

        let referenceExtent = PixelExtent(width: afImageWidth, height: afImageHeight)
        outcome.referenceExtent = referenceExtent
        if let referenceExtent, let imageExtent, referenceExtent != imageExtent {
            outcome.issues.append(
                MetadataIssue(
                    kind: .referenceExtentMismatch,
                    context: contextLabel,
                    detail: "The focus record's reference extent differs from the image extent."
                )
            )
            outcome.uncertainties.append(.referenceExtentMismatch)
        }

        guard let referenceExtent else {
            outcome.geometry = .unavailable(.zeroReferenceExtent)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        guard validAFPoints > 0 else {
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .canon))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        var activeIndices: [Int] = []
        for pointIndex in 0..<validAFPoints {
            let wordIndex = inFocusOffset + (pointIndex / 16)
            let mask = UInt16(1) << (pointIndex % 16)
            if (words[wordIndex] & mask) != 0 {
                activeIndices.append(pointIndex)
            }
        }

        if activeIndices.isEmpty {
            let (threeMasks, overflow4) = maskWords.multipliedReportingOverflow(by: 3)
            let (tailOffset, overflow5) = inFocusOffset.addingReportingOverflow(threeMasks)
            let (fullWordCount, overflow6) = tailOffset.addingReportingOverflow(1)
            if !overflow4, !overflow5, !overflow6, words.count == fullWordCount {
                let primaryAFPoint = words[words.count - 1]
                if primaryAFPoint != 0xFFFF, Int(primaryAFPoint) < validAFPoints {
                    activeIndices = [Int(primaryAFPoint)]
                }
            }
        }

        guard !activeIndices.isEmpty else {
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .canon))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        let halfWidth = Double(referenceExtent.width) / 2.0
        let halfHeight = Double(referenceExtent.height) / 2.0
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity

        for pointIndex in activeIndices {
            let pointWidth = Double(words[8 + pointIndex])
            let pointHeight = Double(words[8 + numAFPoints + pointIndex])
            guard pointWidth > 0, pointHeight > 0 else {
                outcome.geometry = .unavailable(.zeroRegionExtent)
                outcome.uncertainties.append(.focusSuccessNotEstablished)
                return outcome
            }
            let rawX = Int16(bitPattern: words[8 + 2 * numAFPoints + pointIndex])
            let rawY = Int16(bitPattern: words[8 + 3 * numAFPoints + pointIndex])
            // Canon 0x0026 records signed coordinates relative to the center of
            // AFImageWidth x AFImageHeight with +X right and +Y up.
            let centerX = halfWidth + Double(rawX)
            let centerY = halfHeight - Double(rawY)
            minX = min(minX, centerX - pointWidth / 2.0)
            maxX = max(maxX, centerX + pointWidth / 2.0)
            minY = min(minY, centerY - pointHeight / 2.0)
            maxY = max(maxY, centerY + pointHeight / 2.0)
        }

        let combinedCenter = ContinuousPoint(x: (minX + maxX) / 2.0, y: (minY + maxY) / 2.0)
        let combinedSize = ContinuousSize(width: maxX - minX, height: maxY - minY)

        guard
            let region = FocusRegionGeometry(
                space: .storedReference,
                extent: referenceExtent,
                center: combinedCenter,
                size: combinedSize
            )
        else {
            outcome.geometry = .unavailable(.centerOutsideReference)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        outcome.geometry = .region(region)
        outcome.uncertainties.append(contentsOf: [
            .focusSuccessNotEstablished,
            .coordinateIndexConventionUnverified,
            .continuousCoordinateApproximation,
        ])
        return outcome
    }
}
