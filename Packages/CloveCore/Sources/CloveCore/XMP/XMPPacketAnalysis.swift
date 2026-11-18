import Foundation

/// Reading, and the shared analysis a write starts from.
extension XMPPacket {
    /// Where one owned mark sits in the packet, and its decoded text or keywords.
    struct MarkLocation {
        /// The byte ranges a write replaces or removes.
        enum Form {
            case attribute(AttributeSpan)
            case element(content: Range<Int>?, whole: Range<Int>, qualifiedName: String)
            case bagElement(
                content: Range<Int>?, whole: Range<Int>, qualifiedName: String,
                prefixes: [String: String])
        }

        let form: Form
        let text: String
        let keywords: [String]

        init(form: Form, text: String, keywords: [String] = []) {
            self.form = form
            self.text = text
            self.keywords = keywords
        }
    }

    /// One clean `<lr:hierarchicalSubject><rdf:Bag>...</rdf:Bag></lr:hierarchicalSubject>` block
    /// inside an unqualified top-level `rdf:Description`, tracked for keyword removal sync.
    struct HierarchicalSubjectLocation {
        struct Entry {
            let whole: Range<Int>
            let text: String
        }

        let whole: Range<Int>
        let entries: [Entry]
    }

    /// The owned marks of a packet plus the description a write may edit.
    struct Analyzed {
        /// The description a write inserts new marks into, or `nil` when several descriptions
        /// exist, none holds a mark, and at least one is qualified so no place is provable.
        let description: Int?
        let rating: MarkLocation?
        let label: MarkLocation?
        let keywords: MarkLocation?
        let hierarchicalSubjects: [HierarchicalSubjectLocation]
        let marks: XMPMarks
    }

    /// Reads the owned marks (PRD P0-07).
    func read() throws -> XMPMarks {
        try analyze().marks
    }

    /// Inspects the packet once and returns its marks and edit locations.
    ///
    /// Refusals: an owned mark outside a top-level description, a qualified or structured
    /// mark, the same mark twice in one description, or overlapping/qualified marks across
    /// several descriptions. A packet with several descriptions and no marks is readable but
    /// not writable when any description is qualified, which `Analyzed.description` records.
    func analyze() throws -> Analyzed {
        guard !descriptions.isEmpty else { throw XMPCodecError.missingDescription }
        let descriptionIndices = Set(descriptions)
        var marksByDescription: [Int: [XMPProperty: MarkLocation]] = [:]

        for (index, element) in elements.enumerated() {
            if let property = Self.property(named: element.name) {
                guard let parent = element.parent, descriptionIndices.contains(parent) else {
                    throw XMPCodecError.misplacedMark(property)
                }
                switch property {
                case .rating, .label:
                    guard element.attributes.isEmpty, element.children.isEmpty else {
                        throw XMPCodecError.qualifiedMark(property)
                    }
                    let location = MarkLocation(
                        form: .element(
                            content: element.content, whole: element.whole,
                            qualifiedName: element.qualifiedName), text: element.text)
                    try Self.record(location, for: property, in: parent, &marksByDescription)
                case .keywords:
                    let rawKeywords = try parseSubjectKeywords(elementIndex: index)
                    let location = MarkLocation(
                        form: .bagElement(
                            content: element.content,
                            whole: element.whole,
                            qualifiedName: element.qualifiedName,
                            prefixes: element.prefixes),
                        text: "",
                        keywords: rawKeywords)
                    try Self.record(location, for: .keywords, in: parent, &marksByDescription)
                }
                continue
            }
            for (name, value) in element.attributes {
                guard let property = Self.property(named: name) else { continue }
                if descriptionIndices.contains(index) {
                    if property == .keywords {
                        throw XMPCodecError.qualifiedMark(.keywords)
                    }
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
        let target: Int?
        let locations: [XMPProperty: MarkLocation]
        if marked.count > 1 {
            let allUnqualified = marked.keys.allSatisfy { !Self.isQualified(elements[$0]) }
            var merged: [XMPProperty: MarkLocation] = [:]
            var hasOverlap = false
            for description in marked.keys.sorted() {
                for (property, location) in marksByDescription[description] ?? [:] {
                    if merged[property] != nil {
                        hasOverlap = true
                        break
                    }
                    merged[property] = location
                }
                if hasOverlap { break }
            }
            guard allUnqualified && !hasOverlap else {
                throw XMPCodecError.marksInSeveralDescriptions
            }
            target = marked.keys.min()
            locations = merged
        } else if let markedDescription = marked.keys.first {
            target = markedDescription
            locations = marksByDescription[markedDescription] ?? [:]
        } else {
            let allUnqualified = descriptions.allSatisfy { !Self.isQualified(elements[$0]) }
            target = (descriptions.count == 1 || allUnqualified) ? descriptions[0] : nil
            locations = [:]
        }

        let hierarchicalSubjects = collectHierarchicalSubjects()
        let marks = try Self.marks(from: locations)
        return Analyzed(
            description: target,
            rating: locations[.rating],
            label: locations[.label],
            keywords: locations[.keywords],
            hierarchicalSubjects: hierarchicalSubjects,
            marks: marks)
    }

    static func isQualified(_ description: Element) -> Bool {
        for name in [rdfAboutName, rdfNodeIDName, rdfIDName] {
            if let value = description.attributes[name], !value.isEmpty { return true }
        }
        return false
    }

    private func parseSubjectKeywords(elementIndex: Int) throws -> [String] {
        let element = elements[elementIndex]
        guard element.attributes.isEmpty else {
            throw XMPCodecError.qualifiedMark(.keywords)
        }
        if element.children.isEmpty {
            guard Self.trimmingXMLWhitespace(element.text).isEmpty else {
                throw XMPCodecError.qualifiedMark(.keywords)
            }
            return []
        }
        guard element.children.count == 1,
            Self.trimmingXMLWhitespace(element.text).isEmpty
        else {
            throw XMPCodecError.qualifiedMark(.keywords)
        }
        let bag = elements[element.children[0]]
        guard bag.name == Self.rdfBagName,
            bag.attributes.isEmpty,
            Self.trimmingXMLWhitespace(bag.text).isEmpty
        else {
            throw XMPCodecError.qualifiedMark(.keywords)
        }
        var keywords: [String] = []
        keywords.reserveCapacity(bag.children.count)
        for childIndex in bag.children {
            let item = elements[childIndex]
            guard item.name == Self.rdfLiName,
                item.attributes.isEmpty,
                item.children.isEmpty
            else {
                throw XMPCodecError.qualifiedMark(.keywords)
            }
            keywords.append(item.text)
        }
        return keywords
    }

    private func collectHierarchicalSubjects() -> [HierarchicalSubjectLocation] {
        var result: [HierarchicalSubjectLocation] = []
        for descriptionIndex in descriptions {
            let description = elements[descriptionIndex]
            guard !Self.isQualified(description) else { continue }
            for childIndex in description.children {
                let element = elements[childIndex]
                guard element.name == Self.lightroomHierarchicalSubjectName,
                    element.attributes.isEmpty,
                    element.children.count == 1,
                    Self.trimmingXMLWhitespace(element.text).isEmpty
                else { continue }
                let bag = elements[element.children[0]]
                guard bag.name == Self.rdfBagName,
                    bag.attributes.isEmpty,
                    Self.trimmingXMLWhitespace(bag.text).isEmpty
                else { continue }
                var entries: [HierarchicalSubjectLocation.Entry] = []
                var valid = true
                for itemIndex in bag.children {
                    let item = elements[itemIndex]
                    guard item.name == Self.rdfLiName,
                        item.attributes.isEmpty,
                        item.children.isEmpty
                    else {
                        valid = false
                        break
                    }
                    entries.append(
                        HierarchicalSubjectLocation.Entry(whole: item.whole, text: item.text))
                }
                if valid && !entries.isEmpty {
                    result.append(
                        HierarchicalSubjectLocation(whole: element.whole, entries: entries))
                }
            }
        }
        return result
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
        if let keywords = locations[.keywords] {
            marks.keywords = PhotoKeywords.deduplicated(keywords.keywords)
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
