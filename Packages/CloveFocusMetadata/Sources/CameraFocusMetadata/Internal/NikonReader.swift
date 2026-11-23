import Foundation

enum NikonReader {
    private static let focusModeTag: UInt16 = 0x0007
    private static let afInfo2Tag: UInt16 = 0x00B7

    static func read(
        reader: BoundedReader,
        makerNoteOffset: Int,
        makerNoteLength: Int,
        limits: FocusMetadataReader.Limits,
        imageExtent: PixelExtent?
    ) -> VendorReadOutcome? {
        guard makerNoteLength >= 10 else { return nil }
        let prefix: [UInt8]
        do {
            prefix = try reader.read(at: makerNoteOffset, count: 10)
        } catch {
            return nil
        }
        guard prefix.starts(with: [0x4E, 0x69, 0x6B, 0x6F, 0x6E, 0x00]) else {
            return nil
        }

        var outcome = VendorReadOutcome(
            source: .nikonAFInformation,
            geometry: .unavailable(.vendorSemanticsUnverified(vendor: .nikon))
        )
        let makerNoteEnd = makerNoteOffset + makerNoteLength
        let headerOffset = makerNoteOffset + 10
        let header: TIFFHeaderInfo
        do {
            header = try TIFFHeaderParser.read(
                reader: reader,
                at: headerOffset,
                regionEnd: makerNoteEnd
            )
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Nikon embedded TIFF header")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        let context = TIFFContext(
            reader: reader,
            base: headerOffset,
            regionEnd: makerNoteEnd,
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
        } catch let failure as ParseFailure {
            outcome.issues.append(
                MetadataIssue(failure: failure, context: "Nikon MakerNote directory")
            )
            outcome.malformedFocusPath = true
            return outcome
        } catch {
            outcome.malformedFocusPath = true
            return outcome
        }

        if let entry = index.uniqueEntry(tag: focusModeTag), entry.type == 2 {
            do {
                if let value = try context.readASCII(of: entry) {
                    outcome.records.append(
                        VendorRawRecord(
                            tag: UInt32(focusModeTag),
                            name: "Recorded focus mode string",
                            fieldType: entry.type,
                            values: .ascii(value)
                        )
                    )
                }
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Nikon 0x0007")
                )
            } catch {}
        }

        if index.duplicateTags.contains(afInfo2Tag) {
            outcome.issues.append(
                MetadataIssue(kind: .duplicateTag, context: "Nikon 0x00b7")
            )
            outcome.malformedFocusPath = true
            return outcome
        }

        if let entry = index.uniqueEntry(tag: afInfo2Tag) {
            guard entry.type == 7, entry.count >= 4,
                let byteCount = entry.declaredByteCount,
                byteCount <= limits.maximumValueBytes
            else {
                outcome.issues.append(
                    MetadataIssue(
                        kind: .unexpectedFieldShape,
                        context: "Nikon 0x00b7",
                        detail:
                            "Expected TIFF UNDEFINED count >= 4; found type \(entry.type) count \(entry.count)."
                    )
                )
                outcome.malformedFocusPath = true
                return outcome
            }

            do {
                let bytes = try context.readValue(of: entry)
                outcome.records.append(
                    VendorRawRecord(
                        tag: UInt32(afInfo2Tag),
                        name: "AF information block",
                        fieldType: entry.type,
                        values: .unsignedBytes(bytes)
                    )
                )
                decodeAFInfo2(
                    bytes: bytes,
                    byteOrder: context.byteOrder,
                    imageExtent: imageExtent,
                    outcome: &outcome
                )
            } catch let failure as ParseFailure {
                outcome.issues.append(
                    MetadataIssue(failure: failure, context: "Nikon 0x00b7")
                )
                outcome.malformedFocusPath = true
            } catch {
                outcome.malformedFocusPath = true
            }
        }

        if outcome.records.isEmpty {
            outcome.issues.append(
                MetadataIssue(
                    kind: .missingFocusMetadata,
                    context: "Nikon MakerNote",
                    detail: "No observed Nikon focus fields were present."
                )
            )
        }
        return outcome
    }

    private static func decodeAFInfo2(
        bytes: [UInt8],
        byteOrder: TIFFByteOrder,
        imageExtent: PixelExtent?,
        outcome: inout VendorReadOutcome
    ) {
        guard bytes.count >= 4,
            let version = String(bytes: bytes[0..<4], encoding: .ascii)
        else {
            outcome.issues.append(
                MetadataIssue(kind: .truncatedData, context: "Nikon 0x00b7 version")
            )
            outcome.malformedFocusPath = true
            return
        }

        let areaOffset: Int
        switch version {
        case "0300", "0301":
            guard bytes.count >= 54 else {
                outcome.issues.append(
                    MetadataIssue(
                        kind: .truncatedData,
                        context: "Nikon 0x00b7 v\(version)",
                        detail: "Expected at least 54 bytes, found \(bytes.count)."
                    )
                )
                outcome.malformedFocusPath = true
                return
            }
            areaOffset = 42
        case "0400", "0401", "0402":
            guard bytes.count >= 74 else {
                outcome.issues.append(
                    MetadataIssue(
                        kind: .truncatedData,
                        context: "Nikon 0x00b7 v\(version)",
                        detail: "Expected at least 74 bytes, found \(bytes.count)."
                    )
                )
                outcome.malformedFocusPath = true
                return
            }
            areaOffset = 62
        case "0100":
            guard bytes.count >= 5 else {
                outcome.issues.append(
                    MetadataIssue(kind: .truncatedData, context: "Nikon 0x00b7 v0100")
                )
                outcome.malformedFocusPath = true
                return
            }
            guard bytes[4] == 1 else {
                // Non-ContrastDetect OVF capture in v0100 carries only point indices.
                return
            }
            guard bytes.count >= 28 else {
                outcome.issues.append(
                    MetadataIssue(
                        kind: .truncatedData,
                        context: "Nikon 0x00b7 v0100 ContrastDetect",
                        detail: "Expected at least 28 bytes, found \(bytes.count)."
                    )
                )
                outcome.malformedFocusPath = true
                return
            }
            areaOffset = 16
        default:
            // DSLR point-index versions (0101) and Nikon 1 versions (0200, 0201) expose no
            // verified continuous coordinates in 0x00b7.
            return
        }

        outcome.isVerifiedScope = true

        let afImageWidth = readUInt16(bytes, at: areaOffset, byteOrder: byteOrder)
        let afImageHeight = readUInt16(bytes, at: areaOffset + 2, byteOrder: byteOrder)
        let areaX = readUInt16(bytes, at: areaOffset + 4, byteOrder: byteOrder)
        let areaY = readUInt16(bytes, at: areaOffset + 6, byteOrder: byteOrder)
        let areaWidth = readUInt16(bytes, at: areaOffset + 8, byteOrder: byteOrder)
        let areaHeight = readUInt16(bytes, at: areaOffset + 10, byteOrder: byteOrder)

        if afImageWidth == 0 && afImageHeight == 0 && areaX == 0 && areaY == 0
            && areaWidth == 0 && areaHeight == 0
        {
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .nikon))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard
            let referenceExtent = PixelExtent(width: Int(afImageWidth), height: Int(afImageHeight))
        else {
            outcome.geometry = .unavailable(.zeroReferenceExtent)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        outcome.referenceExtent = referenceExtent
        if let imageExtent, imageExtent != referenceExtent {
            outcome.issues.append(
                MetadataIssue(
                    kind: .referenceExtentMismatch,
                    context: "Nikon 0x00b7 reference extent",
                    detail: "The focus record's reference extent differs from the image extent."
                )
            )
            outcome.uncertainties.append(.referenceExtentMismatch)
        }

        if areaX == 0 && areaY == 0 && areaWidth == 0 && areaHeight == 0 {
            outcome.geometry = .unavailable(.noRegionRecorded(vendor: .nikon))
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        guard Int(areaX) <= referenceExtent.width, Int(areaY) <= referenceExtent.height else {
            outcome.geometry = .unavailable(.centerOutsideReference)
            outcome.uncertainties.append(.focusSuccessNotEstablished)
            return
        }

        // Empirically verified on Z 6 / Z fc / Z 30 / Z f / Z 9 / D5600:
        // AFAreaXPosition and AFAreaYPosition are center coordinates in top-left stored space.
        let center = ContinuousPoint(x: Double(areaX), y: Double(areaY))
        if areaWidth > 0, areaHeight > 0 {
            let size = ContinuousSize(width: Double(areaWidth), height: Double(areaHeight))
            if let region = FocusRegionGeometry(
                space: .storedReference,
                extent: referenceExtent,
                center: center,
                size: size
            ) {
                outcome.geometry = .region(region)
                outcome.uncertainties.append(contentsOf: [
                    .focusSuccessNotEstablished,
                    .coordinateIndexConventionUnverified,
                    .continuousCoordinateApproximation,
                ])
            } else {
                outcome.geometry = .unavailable(.centerOutsideReference)
            }
        } else if let location = FocusLocationGeometry(
            space: .storedReference,
            extent: referenceExtent,
            center: center
        ) {
            outcome.geometry = .location(location)
            outcome.uncertainties.append(contentsOf: [
                .focusSuccessNotEstablished,
                .coordinateIndexConventionUnverified,
                .continuousCoordinateApproximation,
            ])
        } else {
            outcome.geometry = .unavailable(.centerOutsideReference)
        }
    }

    private static func readUInt16(
        _ bytes: [UInt8],
        at offset: Int,
        byteOrder: TIFFByteOrder
    ) -> UInt16 {
        switch byteOrder {
        case .littleEndian:
            return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        case .bigEndian:
            return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        }
    }
}
