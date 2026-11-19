import CloveCore
import Foundation

/// Pure keyword parsing, common/mixed derivation, and folder suggestion ranking for batch editing.
enum BatchKeywords {
    private static let separators = CharacterSet(charactersIn: ",，").union(.newlines)

    /// Splits user input on commas (ASCII or fullwidth) and newlines, trims surrounding whitespace,
    /// and deduplicates while preserving exact case and first-seen order.
    static func parse(_ input: String) -> [String] {
        let tokens = input.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return PhotoKeywords.deduplicated(tokens)
    }

    /// Keywords present on every visible target, preserving the first target's keyword order.
    static func commonKeywords(in targets: [GridPhoto]) -> [String] {
        guard let first = targets.first else { return [] }
        let restSets = targets.dropFirst().map { Set($0.marks.keywords) }
        return first.marks.keywords.filter { keyword in
            restSets.allSatisfy { $0.contains(keyword) }
        }
    }

    /// Keywords present on some (but not all) visible targets, preserving first-seen order.
    static func mixedKeywords(in targets: [GridPhoto]) -> [String] {
        guard targets.count > 1 else { return [] }
        let common = Set(commonKeywords(in: targets))
        let all = targets.flatMap(\.marks.keywords).filter { !common.contains($0) }
        return PhotoKeywords.deduplicated(all)
    }

    /// Folder-wide keywords ordered by frequency descending then localized alphabetical order,
    /// excluding keywords already common to every target or already queued in `pending`.
    static func suggestions(
        in allPlacedPhotos: [GridPhoto],
        targets: [GridPhoto],
        excluding pending: [String] = []
    ) -> [String] {
        var counts: [String: Int] = [:]
        for photo in allPlacedPhotos {
            for keyword in photo.marks.keywords where !keyword.isEmpty {
                counts[keyword, default: 0] += 1
            }
        }
        let excluded = Set(commonKeywords(in: targets)).union(pending)
        return counts.keys
            .filter { !excluded.contains($0) }
            .sorted { lhs, rhs in
                let lhsCount = counts[lhs, default: 0]
                let rhsCount = counts[rhs, default: 0]
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                let comparison = lhs.localizedStandardCompare(rhs)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs < rhs
            }
    }
}
