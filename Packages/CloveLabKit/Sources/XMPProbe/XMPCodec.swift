import Foundation
import ImageIO

public enum XMPError: Error, CustomStringConvertible {
    case invalidPacket(String)
    case imageIO(String)
    case unsafeFolder

    public var description: String {
        switch self {
        case .invalidPacket(let reason): "Invalid XMP: \(reason)"
        case .imageIO(let reason): "ImageIO: \(reason)"
        case .unsafeFolder:
            "clove-lab-xmp already exists; choose another folder or remove the previous scratch folder."
        }
    }
}

public struct XMPMarks: Sendable, Equatable {
    /// Raw XMP value, including -1. Reject remains a separate Clove property.
    public var rating: Int
    public var label: String
    public var reject: Bool

    public init(rating: Int = 0, label: String = "", reject: Bool = false) {
        self.rating = rating
        self.label = label
        self.reject = reject
    }
}

public enum XMPApproach: String, CaseIterable, Sendable {
    case imageIO
    case preservingEdit

    public func read(_ data: Data) throws -> XMPMarks {
        if data.isEmpty { return XMPMarks() }
        switch self {
        case .preservingEdit: return try XMPDocument(data).marks()
        case .imageIO:
            guard let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else {
                throw XMPError.imageIO("parse refused")
            }
            func value(_ path: String) -> String? {
                CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String?
            }
            return XMPMarks(
                rating: Int(value("xmp:Rating") ?? "0") ?? 0,
                label: value("xmp:Label") ?? "",
                reject: ["True", "true", "1"].contains(value("clove:Reject") ?? ""))
        }
    }

    public func write(_ data: Data, marks: XMPMarks) throws -> Data {
        guard (-1...5).contains(marks.rating) else {
            throw XMPError.invalidPacket("Rating outside -1...5")
        }
        switch self {
        case .preservingEdit: return try preservingWrite(data, marks: marks)
        case .imageIO: return try imageIOWrite(data, marks: marks)
        }
    }

    private func imageIOWrite(_ data: Data, marks: XMPMarks) throws -> Data {
        let metadata: CGMutableImageMetadata
        if data.isEmpty {
            metadata = CGImageMetadataCreateMutable()
        } else {
            guard let parsed = CGImageMetadataCreateFromXMPData(data as CFData),
                let mutable = CGImageMetadataCreateMutableCopy(parsed)
            else { throw XMPError.imageIO("parse refused") }
            metadata = mutable
        }
        for (uri, prefix) in [(XMPDocument.xmp, "xmp"), (XMPDocument.clove, "clove")] {
            guard
                CGImageMetadataRegisterNamespaceForPrefix(
                    metadata, uri as CFString, prefix as CFString, nil)
            else {
                throw XMPError.imageIO("namespace registration failed")
            }
        }
        for (path, value) in [
            ("xmp:Rating", String(marks.rating)), ("xmp:Label", marks.label),
            ("clove:Reject", marks.reject ? "True" : "False"),
        ] {
            guard
                CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFString)
            else {
                throw XMPError.imageIO("set \(path) failed")
            }
        }
        guard let result = CGImageMetadataCreateXMPData(metadata, nil) else {
            throw XMPError.imageIO("serialization refused")
        }
        return result as Data
    }

    private func preservingWrite(_ data: Data, marks: XMPMarks) throws -> Data {
        if data.isEmpty {
            let packet = """
                <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
                <x:xmpmeta xmlns:x="adobe:ns:meta/">
                 <rdf:RDF xmlns:rdf="\(XMPDocument.rdf)">
                  <rdf:Description rdf:about=""/>
                 </rdf:RDF>
                </x:xmpmeta>
                <?xpacket end="w"?>
                """
            return try preservingWrite(Data(packet.utf8), marks: marks)
        }
        let document = try XMPDocument(data)
        _ = try document.marks()
        guard document.descriptions.count == 1, let node = document.descriptions.first,
            node.attributes[XMPDocument.key(XMPDocument.rdf, "about")] == ""
        else { throw XMPError.invalidPacket("Probe editor requires one empty-about description") }
        let source = String(decoding: data, as: UTF8.self) as NSString
        var edits: [(NSRange, String)] = []
        for (qualified, range) in node.rawAttributes {
            let parts = qualified.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2,
                XMPDocument.markKeys.contains(
                    XMPDocument.key(node.namespaces[parts[0]] ?? "", parts[1]))
            {
                edits.append((range, ""))
            }
        }
        for child in node.children where XMPDocument.markKeys.contains(child.name) {
            guard child.children.isEmpty, child.attributes.isEmpty else {
                throw XMPError.invalidPacket(
                    "Qualified or structured mark requires a richer editor")
            }
            edits.append((child.whole, ""))
        }
        // Local namespace declarations on the new properties cannot conflict
        // with existing prefixes and leave every unrelated declaration untouched.
        let properties = """
            <xmp:Rating xmlns:xmp="\(XMPDocument.xmp)">\(marks.rating)</xmp:Rating>\
            <xmp:Label xmlns:xmp="\(XMPDocument.xmp)">\(escape(marks.label))</xmp:Label>\
            <clove:Reject xmlns:clove="\(XMPDocument.clove)">\(marks.reject ? "True" : "False")</clove:Reject>
            """
        let opening = source.substring(with: node.opening)
        if opening.hasSuffix("/>") {
            edits.append(
                (
                    NSRange(location: NSMaxRange(node.opening) - 2, length: 2),
                    ">\(properties)</\(node.qualifiedName)>"
                ))
        } else {
            edits.append((NSRange(location: NSMaxRange(node.opening), length: 0), properties))
        }
        let result = NSMutableString(string: source)
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        let output = Data((result as String).utf8)
        guard try XMPDocument(output).marks() == marks else {
            throw XMPError.invalidPacket("Read-back mismatch")
        }
        return output
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r", with: "&#13;")
    }
}

/// Independent inspection used for all three approaches, including local SDK outputs.
public enum XMPInspection {
    public static func unknownDataPreserved(before: Data, after: Data) throws -> Bool {
        if before.isEmpty { _ = try XMPDocument(after); return true }
        return try XMPDocument(before).root.canonical(semantic: true, excludingMarks: true)
            == XMPDocument(after).root.canonical(semantic: true, excludingMarks: true)
    }

    public static func representationPreserved(before: Data, after: Data) throws -> Bool {
        if before.isEmpty { return true }
        return try XMPDocument(before).root.canonical(semantic: false, excludingMarks: true)
            == XMPDocument(after).root.canonical(semantic: false, excludingMarks: true)
    }

    public static func inspect(_ data: Data) throws -> XMPMarks { try XMPDocument(data).marks() }
}
