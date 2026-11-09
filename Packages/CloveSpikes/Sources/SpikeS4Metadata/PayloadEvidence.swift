import CryptoKit
import Foundation
import SpikeSupport

public enum MetadataProbeError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

/// A digest is paired with its byte count and role so empty or partial parses cannot pass.
public struct PayloadDigest: Codable, Equatable, Sendable {
    public var role: String
    public var bytes: Int
    public var sha256: String
    /// Diagnostic only; HEIF content comparisons use reference roles, never item IDs.
    public var sourceItemID: Int?

    public init(role: String, data: Data, sourceItemID: Int? = nil) {
        self.role = role
        bytes = data.count
        sha256 = Self.hash(data)
        self.sourceItemID = sourceItemID
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Compressed-byte evidence. HEIF resolves iloc extents for the primary image,
/// grid, tiles and auxiliary image items, excluding Exif/XMP metadata items.
/// TIFF follows next-IFD and SubIFD links and compares each strip/tile and JPEG preview.
/// Unsupported containers fail closed; they never return an empty successful comparison.
public enum PayloadEvidence {
    public static func read(_ data: Data, extension fileExtension: String) throws -> [PayloadDigest]
    {
        let result: [PayloadDigest]
        let ext = fileExtension.lowercased()
        if PhotoExtensions.heif.contains(ext) {
            result = try heif(data)
        } else {
            switch ext {
            case "jpg", "jpeg": result = try jpeg(data)
            case "dng": result = try TIFF(data: data).payloads()
            default:
                throw MetadataProbeError.invalid("Unsupported payload container: \(fileExtension)")
            }
        }
        guard !result.isEmpty, result.allSatisfy({ $0.bytes > 0 }) else {
            throw MetadataProbeError.invalid("No nonempty image payload found")
        }
        return result
    }

    public static func contentMatches(_ before: [PayloadDigest], _ after: [PayloadDigest]) -> Bool {
        !before.isEmpty && before.count == after.count
            && zip(before, after).allSatisfy {
                $0.role == $1.role && $0.bytes == $1.bytes && $0.sha256 == $1.sha256
            }
    }

    public static func jpegEXIFPreviews(_ data: Data) throws -> [PayloadDigest] {
        for segment in try jpegSegments(data) where segment.marker == 0xE1 {
            if segment.data.starts(with: Data("Exif\0\0".utf8)) {
                return try TIFF(data: Data(segment.data.dropFirst(6))).payloads(requireRaw: false)
            }
        }
        return []
    }

    public static func makerNotes(_ data: Data, extension fileExtension: String) throws
        -> [PayloadDigest]
    {
        if fileExtension.lowercased() == "dng" {
            return try TIFF(data: data).makerNotes()
        }
        if ["jpg", "jpeg"].contains(fileExtension.lowercased()) {
            for segment in try jpegSegments(data) where segment.marker == 0xE1 {
                let bytes = segment.data
                if bytes.starts(with: Data("Exif\0\0".utf8)) {
                    return try TIFF(data: Data(bytes.dropFirst(6))).makerNotes()
                }
            }
        }
        if PhotoExtensions.heif.contains(fileExtension.lowercased()) {
            return try heif(data, returnMakerNotes: true)
        }
        return []
    }

    private struct Segment {
        var marker: UInt8
        var data: Data
    }

    private static func jpeg(_ data: Data) throws -> [PayloadDigest] {
        try jpegSegments(data).filter { $0.marker == 0xDA }.enumerated().map {
            PayloadDigest(role: "JPEG/SOS/\($0.offset)", data: $0.element.data)
        }
    }

    private static func jpegSegments(_ data: Data) throws -> [Segment] {
        let reader = Bytes(data: data)
        guard try reader.uint(0, 2) == 0xFFD8 else {
            throw MetadataProbeError.invalid("Missing JPEG SOI")
        }
        var cursor = 2
        var result: [Segment] = []
        while cursor < data.count {
            guard data[cursor] == 0xFF else {
                throw MetadataProbeError.invalid("Invalid JPEG marker")
            }
            while cursor < data.count && data[cursor] == 0xFF { cursor += 1 }
            guard cursor < data.count else {
                throw MetadataProbeError.invalid("Truncated JPEG marker")
            }
            let marker = data[cursor]
            cursor += 1
            if marker == 0xD9 { return result }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { continue }
            let length = try reader.uint(cursor, 2)
            guard length >= 2 else {
                throw MetadataProbeError.invalid("Invalid JPEG segment length")
            }
            let start = cursor + 2
            cursor += length
            _ = try reader.slice(start, length - 2)
            if marker == 0xDA {
                // Include SOS parameters and entropy bytes; retain stuffed FF00 and restart markers.
                while cursor < data.count {
                    if data[cursor] != 0xFF { cursor += 1; continue }
                    var next = cursor + 1
                    while next < data.count && data[next] == 0xFF { next += 1 }
                    guard next < data.count else {
                        throw MetadataProbeError.invalid("Truncated JPEG scan")
                    }
                    if data[next] == 0 || (0xD0...0xD7).contains(data[next]) {
                        cursor = next + 1
                    } else {
                        break
                    }
                }
            }
            result.append(Segment(marker: marker, data: try reader.slice(start, cursor - start)))
        }
        throw MetadataProbeError.invalid("Missing JPEG EOI")
    }

    private struct Box {
        var type: String
        var start: Int
        var end: Int
    }

    private static func boxes(_ reader: Bytes, start: Int, end: Int) throws -> [Box] {
        var cursor = start
        var result: [Box] = []
        while cursor < end {
            var length = try reader.uint(cursor, 4)
            let type = String(decoding: try reader.slice(cursor + 4, 4), as: UTF8.self)
            var header = 8
            if length == 1 {
                length = try reader.uint(cursor + 8, 8)
                header = 16
            } else if length == 0 {
                length = end - cursor
            }
            guard length >= header, length <= end - cursor else {
                throw MetadataProbeError.invalid("Invalid HEIF box length")
            }
            result.append(Box(type: type, start: cursor + header, end: cursor + length))
            cursor += length
        }
        return result
    }

    private static func heif(_ data: Data, returnMakerNotes: Bool = false) throws -> [PayloadDigest]
    {
        let reader = Bytes(data: data)
        let top = try boxes(reader, start: 0, end: data.count)
        guard top.contains(where: { $0.type == "ftyp" }),
            let meta = top.first(where: { $0.type == "meta" })
        else {
            throw MetadataProbeError.invalid("Missing HEIF ftyp/meta")
        }
        let children = try boxes(reader, start: meta.start + 4, end: meta.end)
        guard let iloc = children.first(where: { $0.type == "iloc" }),
            let iinf = children.first(where: { $0.type == "iinf" }),
            let pitm = children.first(where: { $0.type == "pitm" })
        else { throw MetadataProbeError.invalid("Missing HEIF item tables") }
        let primary = try reader.uint(pitm.start + 4, reader.uint(pitm.start, 1) == 0 ? 2 : 4)
        let infoVersion = try reader.uint(iinf.start, 1)
        let infos = try boxes(
            reader, start: iinf.start + 4 + (infoVersion == 0 ? 2 : 4), end: iinf.end)
        var types: [Int: String] = [:]
        for info in infos where info.type == "infe" {
            let version = try reader.uint(info.start, 1)
            guard version == 2 || version == 3 else {
                throw MetadataProbeError.invalid("Unsupported HEIF infe version")
            }
            let width = version == 2 ? 2 : 4
            let id = try reader.uint(info.start + 4, width)
            types[id] = String(
                decoding: try reader.slice(info.start + 4 + width + 2, 4), as: UTF8.self)
        }
        guard let primaryType = types[primary], !["Exif", "mime", "uri "].contains(primaryType)
        else {
            throw MetadataProbeError.invalid("Primary HEIF image is not identified")
        }
        let version = try reader.uint(iloc.start, 1)
        guard version <= 2 else {
            throw MetadataProbeError.invalid("Unsupported HEIF iloc version")
        }
        let sizes = try reader.uint(iloc.start + 4, 1)
        let sizes2 = try reader.uint(iloc.start + 5, 1)
        let offsetSize = sizes >> 4
        let lengthSize = sizes & 15
        let baseSize = sizes2 >> 4
        let indexSize = version > 0 ? sizes2 & 15 : 0
        var cursor = iloc.start + 6
        func take(_ count: Int) throws -> Int {
            guard count <= iloc.end - cursor else {
                throw MetadataProbeError.invalid("Truncated HEIF iloc")
            }
            let value = try reader.uint(cursor, count)
            cursor += count
            return value
        }
        let count = try take(version < 2 ? 2 : 4)
        guard count <= 4096 else { throw MetadataProbeError.invalid("Excessive HEIF items") }
        var payloads: [Int: PayloadDigest] = [:]
        var exifItems: [Data] = []
        for _ in 0..<count {
            let id = try take(version < 2 ? 2 : 4)
            let construction = version > 0 ? try take(2) & 15 : 0
            let reference = try take(2)
            let base = try take(baseSize)
            let extents = try take(2)
            guard let type = types[id] else {
                throw MetadataProbeError.invalid("HEIF item has no type")
            }
            let isImage = !["Exif", "mime", "uri "].contains(type)
            var payload = Data()
            for _ in 0..<extents {
                _ = try take(indexSize)
                let offset = try take(offsetSize)
                let length = try take(lengthSize)
                if isImage || type == "Exif" {
                    guard reference == 0, construction <= 1, length > 0 else {
                        throw MetadataProbeError.invalid(
                            "Unsupported HEIF extent construction/reference")
                    }
                    let start: Int
                    if construction == 1 {
                        guard let idat = children.first(where: { $0.type == "idat" }),
                            base <= idat.end - idat.start, offset <= idat.end - idat.start - base,
                            length <= idat.end - idat.start - base - offset
                        else { throw MetadataProbeError.invalid("HEIF idat extent out of bounds") }
                        start = idat.start + base + offset
                    } else {
                        guard base <= data.count, offset <= data.count - base,
                            length <= data.count - base - offset,
                            top.contains(where: {
                                $0.type == "mdat" && base + offset >= $0.start
                                    && base + offset + length <= $0.end
                            })
                        else { throw MetadataProbeError.invalid("HEIF image extent outside mdat") }
                        start = base + offset
                    }
                    payload.append(try reader.slice(start, length))
                }
            }
            if type == "Exif" { exifItems.append(payload) }
            if isImage {
                guard !payload.isEmpty, payloads[id] == nil else {
                    throw MetadataProbeError.invalid("Empty or duplicate HEIF image item")
                }
                payloads[id] = PayloadDigest(
                    role: type, data: payload, sourceItemID: id
                )
            }
        }
        guard payloads[primary] != nil,
            types.filter({ !["Exif", "mime", "uri "].contains($0.value) }).keys.allSatisfy({
                payloads[$0] != nil
            })
        else { throw MetadataProbeError.invalid("HEIF image item has no compared extent") }
        if returnMakerNotes {
            return try exifItems.flatMap { bytes in
                let exif = Bytes(data: bytes)
                let offset = try exif.uint(0, 4)
                guard offset <= bytes.count - 4 else {
                    throw MetadataProbeError.invalid("Invalid HEIF Exif offset")
                }
                return try TIFF(data: exif.slice(4 + offset, bytes.count - 4 - offset)).makerNotes()
            }
        }
        let references = try heifReferences(reader, children: children, types: types)
        return try heifRoles(primary: primary, payloads: payloads, references: references)
    }

    private struct ItemReference {
        var type: String
        var from: Int
        var to: [Int]
    }

    private static func heifReferences(_ reader: Bytes, children: [Box], types: [Int: String])
        throws
        -> [ItemReference]
    {
        guard let iref = children.first(where: { $0.type == "iref" }) else { return [] }
        let version = try reader.uint(iref.start, 1)
        guard version <= 1 else {
            throw MetadataProbeError.invalid("Unsupported HEIF iref version")
        }
        let width = version == 0 ? 2 : 4
        var result: [ItemReference] = []
        var seen = Set<String>()
        for box in try boxes(reader, start: iref.start + 4, end: iref.end) {
            let from = try reader.uint(box.start, width)
            let count = try reader.uint(box.start + width, 2)
            guard count > 0, box.end - box.start == width + 2 + count * width,
                types[from] != nil, seen.insert("\(from)/\(box.type)").inserted
            else { throw MetadataProbeError.invalid("Invalid or duplicate HEIF reference") }
            let to = try (0..<count).map {
                try reader.uint(box.start + width + 2 + $0 * width, width)
            }
            guard to.allSatisfy({ types[$0] != nil && $0 != from }) else {
                throw MetadataProbeError.invalid("Dangling or self-referencing HEIF item")
            }
            result.append(ItemReference(type: box.type, from: from, to: to))
        }
        return result
    }

    /// Root at pitm. Ordered outgoing dimg edges locate grid tiles and derived inputs.
    /// Incoming auxl/thmb (and other image references) locate auxiliaries by owner.
    /// A canonical edge digest also detects changed ownership/order of shared items.
    private static func heifRoles(
        primary: Int, payloads: [Int: PayloadDigest], references: [ItemReference]
    ) throws -> [PayloadDigest] {
        let imageReferences = references.filter { payloads[$0.from] != nil }.map { ref in
            ItemReference(type: ref.type, from: ref.from, to: ref.to.filter { payloads[$0] != nil })
        }
        var signatures: [Int: String] = [:]
        func signature(_ id: Int, ancestors: Set<Int> = []) throws -> String {
            if let cached = signatures[id] { return cached }
            guard !ancestors.contains(id), ancestors.count < 128, let payload = payloads[id] else {
                throw MetadataProbeError.invalid("Cyclic or excessive HEIF derivation")
            }
            var parts = [payload.role, String(payload.bytes), payload.sha256]
            for ref in imageReferences.filter({ $0.from == id && $0.type == "dimg" }) {
                for target in ref.to {
                    parts.append(try signature(target, ancestors: ancestors.union([id])))
                }
            }
            let value = PayloadDigest.hash(Data(parts.joined(separator: "|").utf8))
            signatures[id] = value
            return value
        }
        for id in payloads.keys { _ = try signature(id) }
        guard let primaryPayload = payloads[primary] else {
            throw MetadataProbeError.invalid("Missing HEIF primary payload")
        }
        var roles = [primary: "HEIF/primary/\(primaryPayload.role)"]
        func role(_ id: Int) throws -> String {
            guard let value = roles[id] else {
                throw MetadataProbeError.invalid("Missing HEIF reference role")
            }
            return value
        }
        var pending = [primary]
        var cursor = 0
        while true {
            if cursor == pending.count {
                // An item not reachable from pitm (for example a camera preview with no
                // reference) is keyed by its content signature, never by its item ID.
                let unassigned = payloads.keys.filter { roles[$0] == nil }
                guard
                    let root = unassigned.min(by: {
                        (signatures[$0] ?? "", $0) < (signatures[$1] ?? "", $1)
                    }), let payload = payloads[root]
                else { break }
                roles[root] = "HEIF/unreferenced/\(signatures[root] ?? "")/\(payload.role)"
                pending.append(root)
            }
            let id = pending[cursor]
            cursor += 1
            let owner = try role(id)
            var neighbors: [(String, Int)] = []
            for ref in imageReferences.filter({ $0.from == id }).sorted(by: { $0.type < $1.type }) {
                for (index, target) in ref.to.enumerated() {
                    neighbors.append(("\(ref.type)/out/\(index)", target))
                }
            }
            let incoming = imageReferences.filter { $0.to.contains(id) }
            for type in Set(incoming.map(\.type)).sorted() {
                let sources = incoming.filter { $0.type == type }.sorted {
                    (signatures[$0.from] ?? "") < (signatures[$1.from] ?? "")
                }
                // Equal source subgraphs are indistinguishable: fail rather than assign by ID.
                guard Set(sources.compactMap { signatures[$0.from] }).count == sources.count else {
                    throw MetadataProbeError.invalid("Ambiguous HEIF image ownership")
                }
                for (index, ref) in sources.enumerated() {
                    neighbors.append(("\(type)/in/\(index)", ref.from))
                }
            }
            for (edge, target) in neighbors where roles[target] == nil {
                guard let payload = payloads[target] else {
                    throw MetadataProbeError.invalid("Missing HEIF referenced payload")
                }
                roles[target] = "\(owner)/\(edge)/\(payload.role)"
                pending.append(target)
            }
        }
        var result = try payloads.map { id, payload in
            var value = payload
            value.role = try role(id)
            return value
        }.sorted { $0.role < $1.role }
        let edges = try imageReferences.map { ref in
            try "\(role(ref.from))/\(ref.type)="
                + ref.to.map { try role($0) }.joined(separator: ",")
        }.sorted().joined(separator: "\n")
        if !edges.isEmpty {
            result.append(PayloadDigest(role: "HEIF/reference-topology", data: Data(edges.utf8)))
        }
        return result
    }
}

private struct Bytes {
    var data: Data
    var littleEndian = false

    func slice(_ offset: Int, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw MetadataProbeError.invalid("Container byte range out of bounds")
        }
        return data.subdata(in: offset..<(offset + count))
    }

    func uint(_ offset: Int, _ count: Int) throws -> Int {
        let bytes = try slice(offset, count)
        guard count <= 8 else { throw MetadataProbeError.invalid("Integer too wide") }
        var value: UInt64 = 0
        for byte in littleEndian ? Array(bytes.reversed()) : Array(bytes) {
            value = (value << 8) | UInt64(byte)
        }
        guard value <= UInt64(Int.max) else { throw MetadataProbeError.invalid("Integer overflow") }
        return Int(value)
    }
}

private struct TIFF {
    var reader: Bytes

    init(data: Data) throws {
        let order = String(decoding: data.prefix(2), as: UTF8.self)
        guard order == "II" || order == "MM" else {
            throw MetadataProbeError.invalid("Invalid TIFF byte order")
        }
        reader = Bytes(data: data, littleEndian: order == "II")
        guard try reader.uint(2, 2) == 42 else {
            throw MetadataProbeError.invalid("Only classic TIFF/DNG is supported (not BigTIFF)")
        }
    }

    private struct Entry {
        var tag: Int
        var type: Int
        var data: Data
        var values: [Int]
    }

    private func directories() throws -> [(String, [Int: Entry])] {
        var pending = [("IFD0", try reader.uint(4, 4))]
        var visited = Set<Int>()
        var result: [(String, [Int: Entry])] = []
        while !pending.isEmpty {
            let (path, offset) = pending.removeFirst()
            if offset == 0 { continue }
            guard visited.insert(offset).inserted, visited.count < 256 else {
                throw MetadataProbeError.invalid("Cyclic or excessive TIFF directory links")
            }
            let count = try reader.uint(offset, 2)
            guard count < 4096 else { throw MetadataProbeError.invalid("Excessive TIFF entries") }
            var entries: [Int: Entry] = [:]
            for index in 0..<count {
                let location = offset + 2 + index * 12
                let tag = try reader.uint(location, 2)
                let type = try reader.uint(location + 2, 2)
                let n = try reader.uint(location + 4, 4)
                let sizes = [
                    1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8,
                    13: 4,
                ]
                guard let size = sizes[type], n <= reader.data.count / size else {
                    throw MetadataProbeError.invalid("Unsupported TIFF field type/count")
                }
                let length = n * size
                let start = length <= 4 ? location + 8 : try reader.uint(location + 8, 4)
                let bytes = try reader.slice(start, length)
                var values: [Int] = []
                if [1, 3, 4, 13].contains(type) {
                    let field = Bytes(data: bytes, littleEndian: reader.littleEndian)
                    values = try (0..<n).map { try field.uint($0 * size, size) }
                }
                entries[tag] = Entry(tag: tag, type: type, data: bytes, values: values)
            }
            result.append((path, entries))
            for tag in [330, 34665, 34853] {
                for (index, link) in (entries[tag]?.values ?? []).enumerated() {
                    pending.append(("\(path)/\(tag)/\(index)", link))
                }
            }
            let next = try reader.uint(offset + 2 + count * 12, 4)
            if next != 0 { pending.append(("\(path)/next", next)) }
        }
        return result
    }

    func payloads(requireRaw: Bool = true) throws -> [PayloadDigest] {
        var result: [PayloadDigest] = []
        for (path, entries) in try directories() {
            for (offsetTag, sizeTag, kind) in [
                (273, 279, "strip"), (324, 325, "tile"), (513, 514, "preview"),
            ] {
                guard let offsets = entries[offsetTag]?.values else { continue }
                guard let counts = entries[sizeTag]?.values, !offsets.isEmpty,
                    offsets.count == counts.count
                else {
                    throw MetadataProbeError.invalid("Missing TIFF byte counts")
                }
                let photometric = entries[262]?.values.first ?? -1
                let role = [32803, 34892].contains(photometric) ? "raw" : kind
                for index in offsets.indices {
                    result.append(
                        PayloadDigest(
                            role: "\(path)/\(role)/\(kind)/\(index)",
                            data: try reader.slice(offsets[index], counts[index])
                        ))
                }
            }
        }
        guard !requireRaw || result.contains(where: { $0.role.contains("/raw/") }) else {
            throw MetadataProbeError.invalid("DNG has no identified CFA/LinearRaw payload")
        }
        return result
    }

    func makerNotes() throws -> [PayloadDigest] {
        try directories().compactMap { path, entries in
            entries[37500].map { PayloadDigest(role: "\(path)/MakerNote", data: $0.data) }
        }
    }
}
