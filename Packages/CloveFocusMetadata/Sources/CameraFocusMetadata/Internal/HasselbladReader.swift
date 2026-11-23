import Foundation

/// Reads Hasselblad unprefixed MakerNote directories (`Exif 0x927c`) for X/CFV-series cameras
/// across both little-endian `.3FR` and big-endian `.FFF` containers.
enum HasselbladReader {
    private static let focusBoxTag: UInt16 = 0x0047
    private static let focusInactiveFlagTag: UInt16 = 0x004A
    private static let focusDebugInfoTag: UInt16 = 0x004B
    private static let sensorWindowTag: UInt16 = 0x0059
    private static let normalizedWidth = 10_000
    private static let normalizedHeight = 10_000

    /// Reads an unprefixed Hasselblad MakerNote directory whose table sits inside
    /// `makerNoteOffset..<makerNoteOffset + makerNoteLength` and whose out-of-line values
    /// are addressed in the enclosing TIFF `context`.
    static func readMakerNote(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        context: TIFFContext,
        limits: FocusMetadataReader.Limits
    ) -> VendorReadOutcome {
        var outcome = VendorReadOutcome(
            source: .hasselbladMakerNote,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .hasselblad))
        )

        guard makerNoteLength >= 2,
            makerNoteOffset <= reader.length - makerNoteLength
        else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .malformedMakerNote,
                    context: "Hasselblad MakerNote directory",
                    detail: "The MakerNote is too short to contain an IFD entry count."
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
                atAbsolute: makerNoteOffset,
                context: context,
                limits: limits,
                visited: &visited,
                depth: 0,
                tableEnd: makerNoteOffset + makerNoteLength
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Hasselblad MakerNote directory")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.issues.append(
                MetadataIssue(
                    kind: .malformedMakerNote,
                    context: "Hasselblad MakerNote directory"
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        VendorReaders.appendSimpleWordRecord(
            tag: focusInactiveFlagTag,
            expectedType: 3,
            expectedCount: 1,
            name: "Hasselblad 0x004a AF status flag",
            index: directory,
            context: context,
            outcome: &outcome
        )
        VendorReaders.appendSimpleWordRecord(
            tag: sensorWindowTag,
            expectedType: 3,
            expectedCount: 5,
            name: "Hasselblad 0x0059 sensor geometry words",
            index: directory,
            context: context,
            outcome: &outcome
        )
        appendDebugSummary(directory: directory, outcome: &outcome)

        if directory.duplicateTags.contains(focusBoxTag) {
            outcome.issues.append(
                MetadataIssue(kind: .duplicateTag, context: "Hasselblad 0x0047")
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        guard let focusEntry = directory.uniqueEntry(tag: focusBoxTag) else {
            if outcome.records.isEmpty {
                outcome.issues.append(
                    MetadataIssue(
                        kind: .missingFocusMetadata,
                        context: "Hasselblad MakerNote",
                        detail: "Tag 0x0047 is not present."
                    )
                )
            }
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        guard focusEntry.type == 3, focusEntry.count >= 5 else {
            outcome.issues.append(
                MetadataIssue(
                    kind: .unexpectedFieldShape,
                    context: "Hasselblad 0x0047",
                    detail:
                        "Expected TIFF SHORT count == 7; found type \(focusEntry.type) count \(focusEntry.count)."
                )
            )
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        let values: [UInt64]
        do {
            guard let readValues = try context.readUnsignedValues(of: focusEntry) else {
                outcome.issues.append(
                    MetadataIssue(kind: .unexpectedFieldShape, context: "Hasselblad 0x0047")
                )
                outcome.uncertainties.append(.focusSuccessNotEstablished)
                outcome.malformedFocusPath = true
                return outcome
            }
            values = readValues
        } catch let failure as ParseFailure {
            outcome.issues.append(MetadataIssue(failure: failure, context: "Hasselblad 0x0047"))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            outcome.malformedFocusPath = true
            return outcome
        }

        outcome.records.append(
            VendorRawRecord(
                tag: UInt32(focusBoxTag),
                name: "Hasselblad 0x0047 focus box words",
                fieldType: focusEntry.type,
                values: .unsignedWords(Array(values.prefix(16)))
            )
        )

        guard values.count == 7 else {
            // Only the 7-word [active, cx, cy, width, height, 0, 0] form is empirically verified.
            outcome.geometry = .unavailable(.vendorSemanticsUnverified(vendor: .hasselblad))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return outcome
        }

        decodeFocusBox(values, outcome: &outcome)
        return outcome
    }

    private static func decodeFocusBox(
        _ values: [UInt64],
        outcome: inout VendorReadOutcome
    ) {
        let activeFlag = values[0]
        if activeFlag == 0 {
            outcome.isVerifiedScope = true
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .hasselblad))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard activeFlag == 1 else {
            outcome.geometry = .unavailable(.vendorSemanticsUnverified(vendor: .hasselblad))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        let centerX = values[1]
        let centerY = values[2]
        let width = values[3]
        let height = values[4]

        if centerX == 0 && centerY == 0 && width == 0 && height == 0 {
            // Verified on Flexbody / non-AF lens exposures: activeFlag == 1 with all-zero box words.
            outcome.isVerifiedScope = true
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .hasselblad))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard let referenceExtent = PixelExtent(width: normalizedWidth, height: normalizedHeight)
        else {
            outcome.geometry = .unavailable(.zeroReferenceExtent)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        outcome.referenceExtent = referenceExtent
        outcome.isVerifiedScope = true

        guard width > 0, height > 0 else {
            outcome.geometry = .unavailable(.zeroRegionExtent)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard centerX <= UInt64(referenceExtent.width),
            centerY <= UInt64(referenceExtent.height)
        else {
            outcome.geometry = .unavailable(.centerOutsideReference)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        if let region = FocusRegionGeometry(
            space: .storedReference,
            extent: referenceExtent,
            center: ContinuousPoint(x: Double(centerX), y: Double(centerY)),
            size: ContinuousSize(width: Double(width), height: Double(height))
        ) {
            outcome.geometry = .region(region)
        } else {
            outcome.geometry = .unavailable(.centerOutsideReference)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
        }
    }

    private static func appendDebugSummary(
        directory: TIFFEntryIndex,
        outcome: inout VendorReadOutcome
    ) {
        if directory.duplicateTags.contains(focusDebugInfoTag) {
            outcome.issues.append(
                MetadataIssue(kind: .duplicateTag, context: "Hasselblad 0x004b")
            )
            return
        }
        guard let entry = directory.uniqueEntry(tag: focusDebugInfoTag),
            let byteCount = entry.declaredByteCount
        else {
            return
        }
        outcome.records.append(
            VendorRawRecord(
                tag: UInt32(focusDebugInfoTag),
                name: "Hasselblad 0x004b debug block byte count",
                fieldType: entry.type,
                values: .unsignedWords([UInt64(byteCount)])
            )
        )
    }
}
