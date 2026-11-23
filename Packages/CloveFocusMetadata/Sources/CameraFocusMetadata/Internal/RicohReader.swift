import Foundation

/// Reads Ricoh `RICOH\0II` AF metadata (IFD0 `0xc634` DNGPrivateData and Exif `0x927c` MakerNote)
/// and legacy `Ricoh\0\0\0` MakerNote directories.
enum RicohReader {
    private static let structuredPrefix: [UInt8] = Array("RICOH\0II".utf8)
    private static let legacyPrefix: [UInt8] = Array("Ricoh\0\0\0".utf8)

    private static let focusSettingTag: UInt16 = 0x000D
    private static let afInfoTag: UInt16 = 0x040C

    /// Reads an `IFD0 0xc634` payload beginning with `RICOH\0II`.
    /// Returns `nil` when `payloadLength` is smaller than the prefix or does not start with `RICOH\0II`.
    static func readDNGPrivateData(
        reader: BoundedReader,
        payloadOffset: Int,
        payloadLength: Int,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> VendorReadOutcome? {
        guard payloadLength >= structuredPrefix.count else { return nil }
        let prefix: [UInt8]
        do {
            prefix = try reader.read(at: payloadOffset, count: structuredPrefix.count)
        } catch let failure as ParseFailure {
            var outcome = VendorReadOutcome(
                source: .ricohPrivateData,
                geometry: .unavailable(.vendorSemanticsUnverified(vendor: .ricoh))
            )
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Ricoh 0xc634 prefix")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            return nil
        }

        guard prefix == structuredPrefix else { return nil }
        return readStructuredDirectory(
            reader: reader,
            blockOffset: payloadOffset,
            blockLength: payloadLength,
            source: .ricohPrivateData,
            contextLabel: "Ricoh 0xc634 payload",
            limits: limits,
            imageExtent: imageExtent
        )
    }

    /// Reads a Ricoh `Exif 0x927c` MakerNote starting with `RICOH\0II` or `Ricoh\0\0\0`.
    static func readMakerNote(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        headerBytes: [UInt8],
        outerContext: TIFFContext,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> (flavor: MakerNoteFlavor, outcome: VendorReadOutcome)? {
        if headerBytes.starts(with: structuredPrefix) {
            let outcome = readStructuredDirectory(
                reader: reader,
                blockOffset: makerNoteOffset,
                blockLength: makerNoteLength,
                source: .ricohMakerNote,
                contextLabel: "Ricoh MakerNote",
                limits: limits,
                imageExtent: imageExtent
            )
            return (.ricoh, outcome)
        }

        if headerBytes.starts(with: legacyPrefix) {
            let outcome = readLegacyMakerNote(
                reader: reader,
                makerNoteOffset: makerNoteOffset,
                makerNoteLength: makerNoteLength,
                outerContext: outerContext,
                limits: limits
            )
            return (.ricohLegacy, outcome)
        }

        return nil
    }

    private static func readStructuredDirectory(
        reader: BoundedReader,
        blockOffset: Int,
        blockLength: Int,
        source: FocusSource,
        contextLabel: String,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> VendorReadOutcome {
        var outcome = VendorReadOutcome(
            source: source,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .ricoh))
        )

        guard blockLength >= structuredPrefix.count + 2,
            blockOffset <= reader.length - blockLength
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .truncatedData,
                    context: contextLabel,
                    detail: "Ricoh block is truncated before the MakerNote directory."
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        let directoryOffset = blockOffset + structuredPrefix.count
        let regionEnd = blockOffset + blockLength
        let context = TIFFContext(
            reader: reader,
            base: blockOffset,
            regionEnd: regionEnd,
            byteOrder: .littleEndian
        )

        let directory: TIFFEntryIndex
        do {
            var visited = Set<Int>()
            directory = try TIFFDirectoryParser.parse(
                reader: reader,
                atAbsolute: directoryOffset,
                context: context,
                limits: limits,
                visited: &visited,
                depth: 0,
                tableEnd: regionEnd
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(MetadataIssue(failure: failure, context: contextLabel))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.issues.append(MetadataIssue(kind: .invalidIFD, context: contextLabel))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        VendorReaders.appendSimpleWordRecord(
            tag: focusSettingTag,
            expectedType: 3,
            expectedCount: 1,
            name: "Recorded Ricoh focus setting word",
            index: directory,
            context: context,
            outcome: &outcome
        )

        if directory.duplicateTags.contains(afInfoTag) {
            outcome.issues.append(
                MetadataIssue(kind: .duplicateTag, context: "\(contextLabel) 0x040c")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        guard let afEntry = directory.uniqueEntry(tag: afInfoTag) else {
            if outcome.records.isEmpty {
                outcome.issues.append(
                    MetadataIssue(
                        kind: .missingFocusMetadata,
                        context: contextLabel,
                        detail: "Tag 0x040c is not present."
                    )
                )
            }
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        guard afEntry.type == 7 || afEntry.type == 1,
            let declaredBytes = afEntry.declaredByteCount,
            declaredBytes >= 14,
            declaredBytes.isMultiple(of: 2)
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unexpectedFieldShape,
                    context: "\(contextLabel) 0x040c",
                    detail:
                        "Expected even-length UNDEFINED/BYTE count >= 14; found type \(afEntry.type) count \(afEntry.count)."
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        guard declaredBytes <= limits.maximumValueBytes else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .entryCountLimitExceeded,
                    context: "\(contextLabel) 0x040c"
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        let payloadBytes: [UInt8]
        do {
            payloadBytes = try context.readValue(of: afEntry)
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "\(contextLabel) 0x040c"))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        guard payloadBytes.count == declaredBytes else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .truncatedData,
                    context: "\(contextLabel) 0x040c"
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        let wordCount = payloadBytes.count / 2
        var words: [UInt16] = []
        words.reserveCapacity(wordCount)
        for index in 0..<wordCount {
            let offset = index * 2
            let word = UInt16(payloadBytes[offset]) | (UInt16(payloadBytes[offset + 1]) << 8)
            words.append(word)
        }

        outcome.records.append(
            VendorRawRecord(
                tag: UInt32(afInfoTag),
                name: "Ricoh 0x040c AF header words",
                fieldType: afEntry.type,
                values: .unsignedWords(words.prefix(7).map { UInt64($0) })
            )
        )

        decodeStructuredAFWords(
            words,
            entryType: afEntry.type,
            contextLabel: contextLabel,
            imageExtent: imageExtent,
            outcome: &outcome
        )
        return outcome
    }

    private static func decodeStructuredAFWords(
        _ words: [UInt16],
        entryType: UInt16,
        contextLabel: String,
        imageExtent: PixelExtent?,
        outcome: inout VendorReadOutcome
    ) {
        guard words.count >= 7 else {
            outcome.issues.append(
                MetadataIssue(kind: .truncatedData, context: "\(contextLabel) 0x040c")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return
        }

        let state = words[0]
        let slotCapacity = Int(words[2])

        if state == 255 {
            // Verified MF / Snap Focus state: 0x040c records state == 255 and zero active zones.
            outcome.isVerifiedScope = true
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .ricoh))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard state == 2 else {
            outcome.geometry = .unavailable(.vendorSemanticsUnverified(vendor: .ricoh))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        let slotWords = slotCapacity.multipliedReportingOverflow(by: 7)
        let requiredWords =
            slotWords.overflow
            ? (partialValue: 0, overflow: true)
            : slotWords.partialValue.addingReportingOverflow(7)
        guard slotCapacity > 0,
            !requiredWords.overflow,
            requiredWords.partialValue <= words.count
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unexpectedFieldShape,
                    context: "\(contextLabel) 0x040c",
                    detail:
                        "Slot capacity \(slotCapacity) does not fit in \(words.count) decoded words."
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return
        }

        struct ActiveSlot {
            let refW: Int
            let refH: Int
            let cx: Int
            let cy: Int
            let width: Int
            let height: Int
            let flags: UInt16
        }

        var activeSlots: [ActiveSlot] = []
        var firstSlotWords: [UInt64]? = nil
        for slotIndex in 0..<slotCapacity {
            let base = 7 + slotIndex * 7
            let refW = Int(words[base])
            let refH = Int(words[base + 1])
            let cx = Int(words[base + 2])
            let cy = Int(words[base + 3])
            let w = Int(words[base + 4])
            let h = Int(words[base + 5])
            let flags = words[base + 6]

            // Flags bit 2 (0x04) distinguishes active in-focus zones (7, 15) from
            // evaluated background cells (3) and unused zero slots (0).
            if (flags & 0x0004) != 0 {
                if firstSlotWords == nil {
                    firstSlotWords = (0..<7).map { UInt64(words[base + $0]) }
                }
                activeSlots.append(
                    ActiveSlot(
                        refW: refW,
                        refH: refH,
                        cx: cx,
                        cy: cy,
                        width: w,
                        height: h,
                        flags: flags
                    )
                )
            }
        }

        if let firstSlotWords {
            outcome.records.append(
                VendorRawRecord(
                    tag: UInt32(afInfoTag),
                    name: "Ricoh 0x040c first active zone words",
                    fieldType: entryType,
                    values: .unsignedWords(firstSlotWords)
                )
            )
        }

        guard let first = activeSlots.first else {
            outcome.isVerifiedScope = true
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .ricoh))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard first.refW > 0, first.refH > 0,
            let referenceExtent = PixelExtent(width: first.refW, height: first.refH)
        else {
            outcome.isVerifiedScope = true
            outcome.geometry = .unavailable(.zeroReferenceExtent)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard
            activeSlots.allSatisfy({
                $0.refW == referenceExtent.width && $0.refH == referenceExtent.height
            })
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unexpectedFieldShape,
                    context: "\(contextLabel) 0x040c",
                    detail: "Active Ricoh AF slots disagree on reference grid dimensions."
                )
            )
            outcome.geometry = .unavailable(.vendorSemanticsUnverified(vendor: .ricoh))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        outcome.referenceExtent = referenceExtent
        outcome.isVerifiedScope = true

        // Guard against images whose pixel buffer was physically transposed (portrait dimensions)
        // while 0x040c remains in the camera's landscape stored grid (e.g. 720x480).
        if let imageExtent,
            imageExtent.width != imageExtent.height,
            referenceExtent.width != referenceExtent.height,
            (imageExtent.width > imageExtent.height)
                != (referenceExtent.width > referenceExtent.height)
        {
            outcome.issues.append(
                MetadataIssue(
                    kind: .referenceExtentMismatch,
                    context: "\(contextLabel) reference extent",
                    detail:
                        "Container image orientation conflicts with the stored 0x040c reference grid."
                )
            )
            outcome.uncertainties.append(.referenceExtentMismatch)
            outcome.geometry = .unavailable(.orientationConflict)
            return
        }

        var minLeft = Double.infinity
        var minTop = Double.infinity
        var maxRight = -Double.infinity
        var maxBottom = -Double.infinity

        for slot in activeSlots {
            guard slot.cx >= 0, slot.cx <= referenceExtent.width,
                slot.cy >= 0, slot.cy <= referenceExtent.height
            else {
                outcome.geometry = .unavailable(.centerOutsideReference)
                outcome.uncertainties.append(.focusSuccessNotEstablished)
                return
            }
            guard slot.width > 0, slot.height > 0 else {
                outcome.geometry = .unavailable(.zeroRegionExtent)
                outcome.uncertainties.append(.focusSuccessNotEstablished)
                return
            }

            let halfW = Double(slot.width) / 2.0
            let halfH = Double(slot.height) / 2.0
            let centerX = Double(slot.cx)
            let centerY = Double(slot.cy)
            minLeft = min(minLeft, centerX - halfW)
            maxRight = max(maxRight, centerX + halfW)
            minTop = min(minTop, centerY - halfH)
            maxBottom = max(maxBottom, centerY + halfH)
        }

        let center = ContinuousPoint(
            x: (minLeft + maxRight) / 2.0,
            y: (minTop + maxBottom) / 2.0
        )
        let size = ContinuousSize(
            width: maxRight - minLeft,
            height: maxBottom - minTop
        )

        if let region = FocusRegionGeometry(
            space: .storedReference,
            extent: referenceExtent,
            center: center,
            size: size
        ) {
            outcome.geometry = .region(region)
        } else {
            outcome.geometry = .unavailable(.centerOutsideReference)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
        }
    }

    private static func readLegacyMakerNote(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        outerContext: TIFFContext,
        limits: FocusMetadataReader.Limits
    ) -> VendorReadOutcome {
        var outcome = VendorReadOutcome(
            source: .ricohMakerNote,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .ricoh))
        )

        let directoryOffset = makerNoteOffset + legacyPrefix.count
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        guard makerNoteLength >= legacyPrefix.count + 2,
            makerNoteOffset <= reader.length - makerNoteLength
        else {
            outcome.issues.append(
                MetadataIssue(kind: .truncatedData, context: "Ricoh legacy MakerNote")
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
                MetadataIssue(failure: failure, context: "Ricoh legacy MakerNote")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.issues.append(
                MetadataIssue(kind: .invalidIFD, context: "Ricoh legacy MakerNote")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        VendorReaders.appendSimpleWordRecord(
            tag: 0x1001,
            expectedType: 3,
            expectedCount: 1,
            name: "Ricoh legacy MakerNote recording mode",
            index: directory,
            context: outerContext,
            outcome: &outcome
        )

        if outcome.records.isEmpty {
            outcome.records.append(
                VendorRawRecord(
                    tag: nil,
                    name: "Ricoh legacy MakerNote entry count",
                    fieldType: 3,
                    values: .unsignedWords([UInt64(directory.entries.count)])
                )
            )
        }

        outcome.uncertainties.append(.focusSuccessNotEstablished)
        return outcome
    }
}
