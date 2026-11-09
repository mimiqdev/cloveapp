import Foundation

/// Reading, and the shared analysis a write starts from.
extension XMPPacket {
    /// Where one owned mark sits in the packet, and its decoded text.
    struct MarkLocation {
        /// The byte ranges a write replaces or removes.
        enum Form {
            case attribute(AttributeSpan)
            case element(content: Range<Int>?, whole: Range<Int>, qualifiedName: String)
        }

        let form: Form
        let text: String
    }

    /// The owned marks of a packet plus the description a write may edit.
    struct Analyzed {
        /// The description a write edits, or `nil` when several descriptions exist and none
        /// holds a mark, so no place is provable.
        let description: Int?
        let rating: MarkLocation?
        let label: MarkLocation?
        let marks: XMPMarks
    }

    /// Reads the owned marks (PRD P0-07).
    func read() throws -> XMPMarks {
        try analyze().marks
    }

    /// Inspects the packet once and returns its marks and edit locations.
    ///
    /// Refusals: an owned mark outside a top-level description, a qualified or structured
    /// mark, the same mark twice in one description, or marks in several descriptions.
    /// A packet with several descriptions and no marks is readable but not writable, which
    /// `Analyzed.description` records (G1 XMP codec row, refusal policy).
    func analyze() throws -> Analyzed {
        guard !descriptions.isEmpty else { throw XMPCodecError.missingDescription }
        let descriptionIndices = Set(descriptions)
        var marksByDescription: [Int: [XMPProperty: MarkLocation]] = [:]

        for (index, element) in elements.enumerated() {
            if let property = Self.property(named: element.name) {
                guard let parent = element.parent, descriptionIndices.contains(parent) else {
                    throw XMPCodecError.misplacedMark(property)
                }
                guard element.attributes.isEmpty, element.children.isEmpty else {
                    throw XMPCodecError.qualifiedMark(property)
                }
                let location = MarkLocation(
                    form: .element(
                        content: element.content, whole: element.whole,
                        qualifiedName: element.qualifiedName), text: element.text)
                try Self.record(location, for: property, in: parent, &marksByDescription)
                continue
            }
            for (name, value) in element.attributes {
                guard let property = Self.property(named: name) else { continue }
                if descriptionIndices.contains(index) {
                    guard let span = element.attributeSpans[name] else {
                        throw XMPCodecError.malformedXML("Missing attribute range")
                    }
                    let location = MarkLocation(form: .attribute(span), text: value)
                    try Self.record(location, for: property, in: index, &marksByDescription)
                } else if Self.property(named: element.name) != nil {
                    throw XMPCodecError.qualifiedMark(property)
                } else {
                    throw XMPCodecError.misplacedMark(property)
                }
            }
        }

        let marked = marksByDescription.filter { !$0.value.isEmpty }
        guard marked.count <= 1 else { throw XMPCodecError.marksInSeveralDescriptions }
        let target: Int?
        if let markedDescription = marked.keys.first {
            target = markedDescription
        } else {
            target = descriptions.count == 1 ? descriptions[0] : nil
        }
        let locations = target.flatMap { marksByDescription[$0] } ?? [:]
        let marks = try Self.marks(from: locations)
        return Analyzed(
            description: target, rating: locations[.rating], label: locations[.label],
            marks: marks)
    }

    private static func record(
        _ location: MarkLocation, for property: XMPProperty, in description: Int,
        _ marksByDescription: inout [Int: [XMPProperty: MarkLocation]]
    ) throws {
        var values = marksByDescription[description] ?? [:]
        guard values[property] == nil else { throw XMPCodecError.duplicateMark(property) }
        values[property] = location
        marksByDescription[description] = values
    }

    /// Turns decoded property text into marks.
    ///
    /// A rating is an XML Schema integer, so surrounding XML whitespace is ignored; the
    /// value itself is otherwise kept exactly, including values outside 0–5 (PRD P0-07).
    /// A label is never trimmed: PRD disk rule 9 keeps its exact external text.
    private static func marks(from locations: [XMPProperty: MarkLocation]) throws -> XMPMarks {
        var marks = XMPMarks()
        if let rating = locations[.rating] {
            let text = Self.trimmingXMLWhitespace(rating.text)
            guard let value = Int(text) else {
                throw XMPCodecError.invalidRating(rating.text)
            }
            marks.rating = XMPRating(value)
        }
        if let label = locations[.label] {
            marks.label = ColourLabel(rawValue: label.text)
        }
        return marks
    }

    private static func trimmingXMLWhitespace(_ text: String) -> String {
        var value = Substring(text)
        while let first = value.first,
            first == " " || first == "\t" || first == "\n"
                || first == "\r"
        {
            value = value.dropFirst()
        }
        while let last = value.last,
            last == " " || last == "\t" || last == "\n"
                || last == "\r"
        {
            value = value.dropLast()
        }
        return String(value)
    }
}
