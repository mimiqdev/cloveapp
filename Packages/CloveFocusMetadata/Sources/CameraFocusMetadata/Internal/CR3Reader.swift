import Foundation

enum CR3Reader {
    private static let canonUUID: [UInt8] = [
        0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0,
        0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48,
    ]

    private struct VendorBoxes {
        var cmt1: BMFFBox?
        var cmt2: BMFFBox?
        var cmt3: BMFFBox?
    }

    static func extract(
        reader: BoundedReader,
        builder: ExtractionBuilder,
        limits: FocusMetadataReader.Limits
    ) {
        let boxes: VendorBoxes
        do {
            boxes = try findVendorBoxes(reader: reader, limits: limits)
        } catch let failure as ParseFailure {
            builder.focusPathMalformed = true
            builder.addIssue(failure: failure, context: "Canon CR3")
            return
        } catch {
            builder.focusPathUnsupported = true
            return
        }

        guard let cmt3 = boxes.cmt3 else {
            builder.focusPathUnsupported = true
            builder.addIssue(
                .unsupportedVendorFocusLayout,
                context: "Canon CR3",
                detail: "The known CMT3 vendor box was not found."
            )
            return
        }

        if let cmt1 = boxes.cmt1 {
            parseCMT1(cmt1, reader: reader, builder: builder, limits: limits)
        }
        if builder.camera == nil {
            builder.camera = CameraIdentity(
                vendor: .canon,
                make: nil,
                model: nil,
                recordedSoftware: nil
            )
        }

        if let cmt2 = boxes.cmt2 {
            parseCMT2(cmt2, reader: reader, builder: builder, limits: limits)
        }

        do {
            let header = try TIFFHeaderParser.read(
                reader: reader,
                at: cmt3.payloadStart,
                regionEnd: cmt3.end
            )
            TIFFMetadataExtractor.extractCanonCMT3(
                reader: reader,
                tiffOffset: cmt3.payloadStart,
                tiffEnd: cmt3.end,
                byteOrder: header.byteOrder,
                builder: builder,
                limits: limits
            )
        } catch let failure as ParseFailure {
            builder.focusPathMalformed = true
            builder.addIssue(failure: failure, context: "Canon CR3 CMT3")
        } catch {
            builder.focusPathMalformed = true
        }
    }

    private static func parseCMT1(
        _ box: BMFFBox,
        reader: BoundedReader,
        builder: ExtractionBuilder,
        limits: FocusMetadataReader.Limits
    ) {
        do {
            let parsed = try readSingleIFD(reader: reader, box: box, limits: limits)
            let make = TIFFMetadataExtractor.readASCII(
                parsed.index,
                tag: 0x010F,
                context: parsed.context,
                builder: builder
            )
            let model = TIFFMetadataExtractor.readASCII(
                parsed.index,
                tag: 0x0110,
                context: parsed.context,
                builder: builder
            )
            let software = TIFFMetadataExtractor.readASCII(
                parsed.index,
                tag: 0x0131,
                context: parsed.context,
                builder: builder
            )
            let detected = TIFFMetadataExtractor.cameraVendor(make: make, model: model)
            let vendor = detected == .unknown ? CameraVendor.canon : detected
            builder.camera = CameraIdentity(
                vendor: vendor,
                make: make,
                model: model,
                recordedSoftware: software
            )
            TIFFMetadataExtractor.readOrientation(
                parsed.index,
                context: parsed.context,
                builder: builder
            )
        } catch let failure as ParseFailure {
            builder.focusPathMalformed = true
            builder.addIssue(failure: failure, context: "Canon CR3 CMT1")
        } catch {
            builder.focusPathMalformed = true
        }
    }

    private static func parseCMT2(
        _ box: BMFFBox,
        reader: BoundedReader,
        builder: ExtractionBuilder,
        limits: FocusMetadataReader.Limits
    ) {
        do {
            let parsed = try readSingleIFD(reader: reader, box: box, limits: limits)
            TIFFMetadataExtractor.readImageExtent(
                parsed.index,
                context: parsed.context,
                builder: builder
            )
            if builder.imageExtent == nil {
                var visited: Set<Int> = []
                if let nestedExif = TIFFMetadataExtractor.readExifDirectory(
                    parsed.index,
                    reader: reader,
                    context: parsed.context,
                    limits: limits,
                    visited: &visited,
                    builder: builder
                ) {
                    TIFFMetadataExtractor.readImageExtent(
                        nestedExif,
                        context: parsed.context,
                        builder: builder
                    )
                }
            }
        } catch let failure as ParseFailure {
            builder.focusPathMalformed = true
            builder.addIssue(failure: failure, context: "Canon CR3 CMT2")
        } catch {
            builder.focusPathMalformed = true
        }
    }

    private static func readSingleIFD(
        reader: BoundedReader,
        box: BMFFBox,
        limits: FocusMetadataReader.Limits
    ) throws -> (index: TIFFEntryIndex, context: TIFFContext) {
        let header = try TIFFHeaderParser.read(
            reader: reader,
            at: box.payloadStart,
            regionEnd: box.end
        )
        let context = TIFFContext(
            reader: reader,
            base: box.payloadStart,
            regionEnd: box.end,
            byteOrder: header.byteOrder
        )
        var visited: Set<Int> = []
        let absolute = try context.absolute(relativeOffset: header.firstIFDOffset)
        let index = try TIFFDirectoryParser.parse(
            reader: reader,
            atAbsolute: absolute,
            context: context,
            limits: limits,
            visited: &visited,
            depth: 0
        )
        return (index, context)
    }

    private static func findVendorBoxes(
        reader: BoundedReader,
        limits: FocusMetadataReader.Limits
    ) throws -> VendorBoxes {
        var counter = 0
        var moov: BMFFBox?
        try BMFFParser.forEachBox(
            reader: reader,
            start: 0,
            end: reader.length,
            depth: 0,
            limits: limits,
            boxCounter: &counter
        ) { box in
            if box.type == "moov" {
                moov = box
            }
        }
        guard let moov else { return VendorBoxes() }

        var uuidBox: BMFFBox?
        var innerCounter = 0
        try BMFFParser.forEachBox(
            reader: reader,
            start: moov.payloadStart,
            end: moov.end,
            depth: 1,
            limits: limits,
            boxCounter: &innerCounter
        ) { box in
            guard box.type == "uuid",
                box.payloadLength >= 16,
                uuidBox == nil
            else { return }
            let identifier = try reader.read(at: box.payloadStart, count: 16)
            if identifier == canonUUID {
                uuidBox = box
            }
        }
        guard let uuidBox else { return VendorBoxes() }

        var result = VendorBoxes()
        var vendorCounter = 0
        try BMFFParser.forEachBox(
            reader: reader,
            start: uuidBox.payloadStart + 16,
            end: uuidBox.end,
            depth: 2,
            limits: limits,
            boxCounter: &vendorCounter
        ) { box in
            switch box.type {
            case "CMT1" where result.cmt1 == nil:
                result.cmt1 = box
            case "CMT2" where result.cmt2 == nil:
                result.cmt2 = box
            case "CMT3" where result.cmt3 == nil:
                result.cmt3 = box
            default:
                break
            }
        }
        return result
    }
}
