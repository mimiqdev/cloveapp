import Foundation
import Testing

import CloveCore

/// Checks the code's themes and tokens against the design handoff, token by token.
///
/// `design/handoff/tokens/clove-themes.json` is the source (V1 in the development plan), so this
/// suite reads the committed file instead of repeating its values. A change to the file without a
/// matching change in ``CloveTheme`` fails here, and so does a typo in either one.
@Suite("Theme token file")
struct ThemeTokenFileTests {
    /// Every theme and token in the file matches the code, in the file's order.
    @Test func tokensMatchTheDesignTokenFile() throws {
        let file = try ThemeTokenFile.load()
        #expect(file.themes.count == CloveTheme.allCases.count)

        for (index, entry) in file.themes.enumerated() {
            let theme = CloveTheme.allCases[index]
            #expect(entry.id == theme.rawValue)
            #expect(entry.name == theme.name)
            #expect(entry.appearance.rawValue == theme.appearance.rawValue)

            // The file holds the 20 colour tokens plus opacity/rejected, and nothing else.
            let expectedKeys = Set(ThemeToken.allCases.map(\.rawValue)).union(["opacity/rejected"])
            #expect(Set(entry.tokens.keys) == expectedKeys, "\(entry.id) token set")

            for token in ThemeToken.allCases {
                let expected = try #require(entry.colours[token.rawValue], "\(entry.id) \(token)")
                #expect(
                    Self.components(of: theme.tokens[token]) == expected,
                    "\(entry.id) \(token.rawValue): \(componentsText(Self.components(of: theme.tokens[token]))) is not \(componentsText(expected))"
                )
            }

            let opacity = try #require(entry.numbers["opacity/rejected"], "\(entry.id) opacity")
            #expect(theme.tokens.rejectedOpacity == opacity, "\(entry.id) opacity/rejected")
        }
    }

    /// The file's documented Swift names follow the token names, so `Color.clove` can use them.
    @Test func documentedSwiftNamesFollowTheTokenNames() throws {
        let file = try ThemeTokenFile.load()
        let colourNames = Set(ThemeToken.allCases.map(\.rawValue))
        #expect(Set(file.tokenDocs.keys) == colourNames.union(["opacity/rejected"]))

        for token in ThemeToken.allCases {
            let doc = try #require(file.tokenDocs[token.rawValue])
            let dottedName = token.rawValue.replacingOccurrences(of: "/", with: ".")
            #expect(doc.swiftName == "Color.clove.\(dottedName)", "\(token.rawValue)")
        }
        #expect(file.tokenDocs["opacity/rejected"]?.swiftName == nil)
    }

    /// Every theme's tokens are colours and an opacity inside their range, which the RGBA model
    /// assumes.
    @Test func everyTokenStaysInsideItsRange() {
        for theme in CloveTheme.allCases {
            for token in ThemeToken.allCases {
                let colour = theme.tokens[token]
                for component in [colour.red, colour.green, colour.blue, colour.alpha] {
                    #expect((0...1).contains(component), "\(theme.id) \(token.rawValue)")
                }
            }
            #expect((0...1).contains(theme.tokens.rejectedOpacity), "\(theme.id)")
        }
    }

    /// The RGBA components as 8-bit values, the precision the file stores.
    private static func components(of colour: ThemeColour) -> [Int] {
        [colour.red, colour.green, colour.blue, colour.alpha].map {
            Int((($0 * 255).rounded()))
        }
    }
}

/// The parts of `clove-themes.json` this suite reads.
private struct ThemeTokenFile {
    /// One theme entry: its identity and its tokens.
    struct ThemeEntry {
        /// The stored `id`.
        let id: String
        /// The display `name`.
        let name: String
        /// The stored `appearance`.
        let appearance: ThemeAppearance
        /// Every raw token string, for the token-set check.
        let tokens: [String: Any]
        /// The colour tokens, as 8-bit RGBA components.
        let colours: [String: [Int]]
        /// The numeric tokens; the file has one, `opacity/rejected`.
        let numbers: [String: Double]
    }

    /// What the file documents for one token.
    struct TokenDoc {
        /// The token's `type`.
        let type: String
        /// The documented Swift name, absent for the numeric token.
        let swiftName: String?
    }

    /// The themes in the file's order.
    let themes: [ThemeEntry]
    /// The per-token documentation keyed by raw token string.
    let tokenDocs: [String: TokenDoc]

    /// Reads the committed file, found by walking up from this test file to the repository root.
    static func load() throws -> ThemeTokenFile {
        let url = try #require(tokenFileURL, "design/handoff/tokens/clove-themes.json is missing")
        let data = try Data(contentsOf: url)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "The token file is not a JSON object")

        let themes = try (root["themes"] as? [[String: Any]] ?? []).map { entry in
            let tokens = try #require(entry["tokens"] as? [String: Any])
            let appearance = try #require(ThemeAppearance(rawValue: try text(entry, "appearance")))
            var colours: [String: [Int]] = [:]
            var numbers: [String: Double] = [:]
            for (name, value) in tokens {
                if let hex = value as? String {
                    colours[name] = try parseHex(hex)
                } else if let number = value as? NSNumber {
                    numbers[name] = number.doubleValue
                } else {
                    Issue.record("Unreadable token \(name)")
                }
            }
            return ThemeEntry(
                id: try text(entry, "id"),
                name: try text(entry, "name"),
                appearance: appearance,
                tokens: tokens,
                colours: colours,
                numbers: numbers)
        }

        let docs = (root["tokenDocs"] as? [String: Any] ?? [:]).mapValues { value in
            let entry = value as? [String: Any] ?? [:]
            return TokenDoc(
                type: entry["type"] as? String ?? "", swiftName: entry["swiftName"] as? String)
        }
        return ThemeTokenFile(themes: themes, tokenDocs: docs)
    }

    /// The committed token file, found by walking up from this test file to the repository root.
    private static let tokenFileURL: URL? = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            let candidate = url.appending(path: "design/handoff/tokens/clove-themes.json")
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }()

    /// Reads a required string field.
    private static func text(_ entry: [String: Any], _ key: String) throws -> String {
        try #require(entry[key] as? String, "Missing \(key)")
    }

    /// Parses the file's `#RRGGBB` or `#RRGGBBAA` spelling into 8-bit RGBA components.
    private static func parseHex(_ hex: String) throws -> [Int] {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        #expect(digits.count == 6 || digits.count == 8, "\(hex)")
        let bytes = stride(from: 0, to: digits.count, by: 2).map { offset -> Int in
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: 2)
            return Int(digits[start..<end], radix: 16) ?? -1
        }
        return digits.count == 6 ? bytes + [255] : bytes
    }
}

/// A readable RGBA listing for a failure message.
private func componentsText(_ components: [Int]) -> String {
    components.map(String.init).joined(separator: "/")
}
