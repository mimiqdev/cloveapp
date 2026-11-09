import Foundation
import Testing

import CloveCore

/// Runs `body` and returns the codec error it threw, recording an issue otherwise.
func xmpError(
    _ body: () throws -> Void, sourceLocation: SourceLocation = #_sourceLocation
) -> XMPCodecError? {
    do {
        try body()
        Issue.record("Expected the codec to refuse", sourceLocation: sourceLocation)
        return nil
    } catch let error as XMPCodecError {
        return error
    } catch {
        Issue.record(error, sourceLocation: sourceLocation)
        return nil
    }
}

func isMalformedXML(_ error: XMPCodecError?) -> Bool {
    guard case .some(.malformedXML) = error else { return false }
    return true
}

/// A minimal description packet for synthetic shapes.
func xmpDescriptionPacket(
    namespaces: String = "xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"",
    attributes: String = "",
    body: String = ""
) -> Data {
    let extra = attributes.isEmpty ? "" : " \(attributes)"
    if body.isEmpty {
        return xmpPacket("<rdf:Description rdf:about=\"\" \(namespaces)\(extra)/>")
    }
    return xmpPacket(
        """
        <rdf:Description rdf:about="" \(namespaces)\(extra)>
        \(body)
          </rdf:Description>
        """)
}

/// How many times `needle` occurs in `text`, without overlapping matches.
func occurrences(of needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var search = text.startIndex..<text.endIndex
    while let found = text.range(of: needle, range: search) {
        count += 1
        search = found.upperBound..<text.endIndex
    }
    return count
}
