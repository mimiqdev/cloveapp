import Foundation
import SpikeSupport
import Testing

@testable import SpikeS3XMP

@Test func s3DescriptorMatchesThePlan() {
    #expect(SpikeS3XMP.descriptor.id == "S3")
    #expect(!SpikeS3XMP.descriptor.question.isEmpty)
}

@Test(arguments: XMPFixtures.packets.keys.sorted())
func bundledPacketsMatchRepository(fixture: String) throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    #expect(
        try Data(contentsOf: root.appendingPathComponent("fixtures/xmp/\(fixture)"))
            == XMPFixtures.packets[fixture])
}

@Test(arguments: XMPFixtures.packets.keys.sorted(), XMPApproach.allCases)
func roundTripEveryFixture(fixture: String, approach: XMPApproach) throws {
    let original = try #require(XMPFixtures.packets[fixture])
    let measurements = XMPSuite.roundTrip(original, fixture: fixture, approach: approach)
    if let path = ProcessInfo.processInfo.environment["S3_REPORT_DIR"],
        let output = try? approach.write(original, marks: XMPSuite.requested)
    {
        let directory = URL(fileURLWithPath: path).appendingPathComponent(approach.rawValue)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try output.write(to: directory.appendingPathComponent(fixture))
    }
    if fixture == "malformed.xmp" {
        let expected = approach == .imageIO ? "roundtrip-invalid-output" : "roundtrip-refused"
        #expect(measurements.contains { $0.name == expected })
    } else if fixture == "empty-description.xmp" && approach == .imageIO {
        #expect(measurements.contains { $0.name == "roundtrip-refused" })
    } else {
        #expect(measurements.contains { $0.name == "marks-confirmed" && $0.value == 1 })
        if approach == .preservingEdit {
            #expect(measurements.contains { $0.name == "unknown-data-preserved" && $0.value == 1 })
            #expect(
                measurements.contains {
                    $0.name == "unknown-representation-preserved" && $0.value == 1
                })
            if !original.isEmpty {
                let source = String(decoding: original, as: UTF8.self) as NSString
                let output = String(
                    decoding: try approach.write(original, marks: XMPSuite.requested), as: UTF8.self
                )
                for node in try XMPDocument(original).descriptions {
                    for child in node.children where !XMPDocument.markKeys.contains(child.name) {
                        #expect(output.contains(source.substring(with: child.whole)))
                    }
                    for (qualified, range) in node.rawAttributes {
                        let parts = qualified.split(separator: ":", maxSplits: 1).map(String.init)
                        let key =
                            parts.count == 2
                            ? XMPDocument.key(node.namespaces[parts[0]] ?? "", parts[1]) : qualified
                        if !XMPDocument.markKeys.contains(key) {
                            #expect(output.contains(source.substring(with: range)))
                        }
                    }
                }
            }
        }
    }
}

@Test func customEditorHandlesAliasesElementsEscapingAndComments() throws {
    let source = Data(
        """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <r:RDF xmlns:r="\(XMPDocument.rdf)" xmlns:p="\(XMPDocument.xmp)">
        <r:Description r:about="" xmlns:q="urn:unknown" q:note="a > b">
        <!-- keep xmp:Rating="5" and > here -->
        <p:Rating>4</p:Rating><p:Label><![CDATA[Blue]]></p:Label>
        <q:tree><q:child xml:lang="en">Ω &amp; café</q:child></q:tree>
        </r:Description></r:RDF><?xpacket end="w"?>
        """.utf8)
    let requested = XMPMarks(rating: 5, label: "A & B < C > D\rΩ", reject: true)
    let output = try XMPApproach.preservingEdit.write(source, marks: requested)
    #expect(try XMPApproach.preservingEdit.read(output) == requested)
    #expect(try XMPInspection.unknownDataPreserved(before: source, after: output))
    let string = String(decoding: output, as: UTF8.self)
    #expect(string.contains("<!-- keep xmp:Rating=\"5\" and > here -->"))
    #expect(string.contains("<q:tree><q:child xml:lang=\"en\">Ω &amp; café</q:child></q:tree>"))
}

@Test func customEditorRefusesAmbiguousOrUnsafePackets() {
    for body in [
        "<x:Rating>1</x:Rating><x:Rating>2</x:Rating>",
        "<x:Rating rdf:resource=\"urn:value\"/>",
    ] {
        let packet = Data(
            """
            <rdf:RDF xmlns:rdf="\(XMPDocument.rdf)" xmlns:x="\(XMPDocument.xmp)">
            <rdf:Description rdf:about="">\(body)</rdf:Description></rdf:RDF>
            """.utf8)
        #expect(throws: (any Error).self) {
            try XMPApproach.preservingEdit.write(packet, marks: XMPSuite.requested)
        }
    }
    let dtd = Data("<!DOCTYPE x [<!ENTITY ex SYSTEM 'file:///etc/passwd'>]><x/>".utf8)
    #expect(throws: (any Error).self) {
        try XMPApproach.preservingEdit.write(dtd, marks: XMPSuite.requested)
    }
}

@Test func rejectsAndEmptyPackets() throws {
    let minusOne = try XMPApproach.preservingEdit.read(XMPFixtures.packets["rating-minus-one.xmp"]!)
    #expect(minusOne.rating == -1)
    #expect(!minusOne.reject)
    for approach in XMPApproach.allCases {
        let output = try approach.write(Data(), marks: XMPSuite.requested)
        #expect(try XMPInspection.inspect(output) == XMPSuite.requested)
        let string = String(decoding: output, as: UTF8.self)
        #expect(string.contains("<?xpacket begin=") == (approach == .preservingEdit))
        #expect(string.contains("W5M0MpCehiHzreSzNTczkc9d") == (approach == .preservingEdit))
        #expect(string.contains("<?xpacket end=") == (approach == .preservingEdit))
    }
}

@Test func unknownDataComparatorDetectsLossAndSequenceChanges() throws {
    let original = XMPFixtures.packets["custom-namespace-nested.xmp"]!
    let source = String(decoding: original, as: UTF8.self)
    for changed in [
        source.replacingOccurrences(of: "<acme:Revision>7</acme:Revision>", with: ""),
        source.replacingOccurrences(
            of: "<acme:Strength>0.62</acme:Strength>", with: "<acme:Strength>0.63</acme:Strength>"),
        source.replacingOccurrences(of: "rdf:datatype=", with: "rdf:resource="),
    ] {
        #expect(
            try !XMPInspection.unknownDataPreserved(before: original, after: Data(changed.utf8)))
    }
    let ordered = Data(
        """
        <rdf:RDF xmlns:rdf="\(XMPDocument.rdf)" xmlns:a="urn:a">
        <rdf:Description rdf:about=""><a:list><rdf:Seq><rdf:li>A</rdf:li><rdf:li>B</rdf:li></rdf:Seq></a:list></rdf:Description></rdf:RDF>
        """.utf8)
    let reordered = Data(
        String(decoding: ordered, as: UTF8.self).replacingOccurrences(
            of: "<rdf:li>A</rdf:li><rdf:li>B</rdf:li>", with: "<rdf:li>B</rdf:li><rdf:li>A</rdf:li>"
        ).utf8)
    #expect(try !XMPInspection.unknownDataPreserved(before: ordered, after: reordered))
}

@Test func atomicSuiteAndFailureCleanup() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("s3-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = XMPSuite.run(in: root)
    #expect(report.context["fileSystem"] == "apfs")
    #expect(report.context["scratchRemains"] == "false")
    #expect(
        report.measurements.filter { $0.name == "atomic-confirmed" && $0.value == 1 }.count == 12)
    #expect(
        report.measurements.filter { $0.name == "temporary-remains" && $0.value == 0 }.count == 12)
    if let path = ProcessInfo.processInfo.environment["S3_REPORT_DIR"] {
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try report.write(to: directory.appendingPathComponent("clove-lab-S3-macos.json"))
    }
    for method in XMPAtomicMethod.allCases {
        let missing = root.appendingPathComponent("missing/target.xmp")
        #expect(throws: (any Error).self) {
            try XMPAtomicWriter.write(
                Data("test".utf8), to: missing, method: method, coordinated: false)
        }
        let target = root.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: target.appendingPathComponent("sentinel"))
        #expect(throws: (any Error).self) {
            try XMPAtomicWriter.write(
                Data("test".utf8), to: target, method: method, coordinated: false)
        }
        #expect(
            try Data(contentsOf: target.appendingPathComponent("sentinel")) == Data("keep".utf8))
        try FileManager.default.removeItem(at: target)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}

@Test func preexistingScratchIsNeverRemoved() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("s3-\(UUID())")
    let scratch = root.appendingPathComponent("clove-lab-s3")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sentinel = scratch.appendingPathComponent("sentinel")
    try Data("keep".utf8).write(to: sentinel)
    let report = XMPSuite.run(in: root)
    #expect(report.notes.contains { $0.contains("already exists") })
    #expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
}

@Test(.enabled(if: Fixtures.set("name-collision") != nil))
func namingOnCollisionSet() throws {
    let root = try #require(Fixtures.set("name-collision"))
    let folder = root.appendingPathComponent("DCIM/100CANON")
    let raw = folder.appendingPathComponent("IMG_0001.CR3")
    let jpg = folder.appendingPathComponent("IMG_0001.JPG")
    #expect(FileManager.default.fileExists(atPath: raw.path))
    #expect(FileManager.default.fileExists(atPath: jpg.path))
    #expect(XMPSidecarNaming.sidecar(for: raw) == XMPSidecarNaming.sidecar(for: jpg))
    #expect(XMPSidecarNaming.sidecar(for: raw).lastPathComponent == "IMG_0001.xmp")
    #expect(XMPSidecarNaming.sidecar(for: raw) != folder.appendingPathComponent("IMG_0001.CR3.xmp"))
    // Enumerate rather than opening lowercase paths: case-sensitive volumes exist.
    let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(entries.contains { $0.lowercased() == "img_0001.xmp" })
}

@Test(.enabled(if: Fixtures.set("xmp-interop") != nil))
func cachedInteropSet() throws {
    let root = try #require(Fixtures.set("xmp-interop"))
    let enumerator = try #require(
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var count = 0
    for case let url as URL in enumerator where url.pathExtension.lowercased() == "xmp" {
        let data = try Data(contentsOf: url)
        for approach in XMPApproach.allCases {
            let results = XMPSuite.roundTrip(data, fixture: url.path, approach: approach)
            #expect(
                results.contains {
                    $0.name == "marks-confirmed" || $0.name == "roundtrip-refused"
                        || $0.name == "roundtrip-invalid-output"
                })
        }
        count += 1
    }
    #expect(count == 11)
}

@Test func inspectLocalSDKOutputsWhenRequested() throws {
    guard let path = ProcessInfo.processInfo.environment["S3_SDK_OUTPUT_DIR"] else { return }
    for (name, original) in XMPFixtures.packets.sorted(by: { $0.key < $1.key }) {
        let output = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent(name))
        #expect(try XMPInspection.inspect(output) == XMPSuite.requested)
        if name == "malformed.xmp" {
            print("S3 SDK malformed.xmp: repaired to well-formed XML")
        } else {
            print(
                "S3 SDK \(name): semantic=\(try XMPInspection.unknownDataPreserved(before: original, after: output)) representation=\(try XMPInspection.representationPreserved(before: original, after: output))"
            )
        }
    }
}
