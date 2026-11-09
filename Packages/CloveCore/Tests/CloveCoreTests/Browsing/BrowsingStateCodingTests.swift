import Foundation
import Testing

import CloveCore

/// The scene's stored form: a round trip keeps every part, and anything unreadable starts at
/// entry (PRD P0-14).
@Suite struct BrowsingStateCodingTests {
    @Test func roundTripKeepsEveryPartOfTheState() throws {
        let saved = BrowsingFixtures.saved
        let data = try #require(saved.encoded())
        #expect(BrowsingState.decoded(from: data) == saved)
    }

    @Test func roundTripKeepsAnEntryStateAtEntry() throws {
        let data = try #require(BrowsingState.entry.encoded())
        #expect(BrowsingState.decoded(from: data) == .entry)
    }

    @Test func missingDataStartsAtEntry() {
        #expect(BrowsingState.decoded(from: nil) == .entry)
    }

    @Test func unreadableDataStartsAtEntry() {
        #expect(BrowsingState.decoded(from: Data("not a browsing state".utf8)) == .entry)
    }

    @Test func olderFormStartsAtEntry() throws {
        let data = try reversioned(BrowsingFixtures.saved, to: 0)
        // An older scene keeps its bytes; the launch simply starts at entry.
        #expect(BrowsingState.decoded(from: data) == .entry)
    }

    @Test func newerFormStartsAtEntry() throws {
        let data = try reversioned(BrowsingFixtures.saved, to: BrowsingState.encodedVersion + 1)
        #expect(BrowsingState.decoded(from: data) == .entry)
    }

    @Test func unknownSpellingStartsAtEntry() throws {
        let data = try rewritten(BrowsingFixtures.saved, setting: "route", to: "filmstrip")
        #expect(BrowsingState.decoded(from: data) == .entry)
    }

    @Test func unknownFilterKindStartsAtEntry() throws {
        let data = try rewritten(BrowsingFixtures.saved, setting: "filter", to: ["kind": "stars"])
        #expect(BrowsingState.decoded(from: data) == .entry)
    }

    @Test func selectionRoundTripsEveryMember() throws {
        var saved = BrowsingFixtures.saved
        saved.selection = [BrowsingFixtures.delta, BrowsingFixtures.alpha]
        let data = try #require(saved.encoded())
        #expect(BrowsingState.decoded(from: data).selection == saved.selection)
    }

    /// The encoded form of a state with one top-level value replaced.
    private func rewritten(_ state: BrowsingState, setting key: String, to value: Any) throws
        -> Data
    {
        let encoded = try #require(state.encoded())
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// The same form, carrying another version.
    private func reversioned(_ state: BrowsingState, to version: Int) throws -> Data {
        try rewritten(state, setting: "version", to: version)
    }
}
