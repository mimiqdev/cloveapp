import Foundation
import Testing

import CloveCore

/// How I4's capture wall clock becomes C8's ordering instant (PRD P0-03, G1 decision 3).
@Suite("Capture wall time")
struct CaptureWallTimeTests {
    private let utc = Calendar(identifier: .gregorian)

    /// The wall clock EXIF stores, read here the way the metadata parser reads it: components
    /// in UTC as a zone-free surrogate.
    private func wallTime(
        year: Int = 2024, month: Int = 2, day: Int = 29,
        hour: Int = 12, minute: Int = 34, second: Int = 56, nanosecond: Int = 7_000_000
    ) throws -> Date {
        var calendar = utc
        calendar.timeZone = .gmt
        return try #require(
            calendar.date(
                from: DateComponents(
                    year: year, month: month, day: day, hour: hour, minute: minute,
                    second: second, nanosecond: nanosecond)))
    }

    @Test func anOffsetGivesTheExactInstant() throws {
        let wall = try wallTime()
        let time = PhotoTime(captureWallTime: wall, utcOffsetSeconds: 19_800, in: .gmt)

        #expect(time.source == .captureMetadata)
        #expect(time.hasUTCOffset)
        #expect(abs(time.instant.timeIntervalSince(wall.addingTimeInterval(-19_800))) < 1e-6)
        // Capture metadata keeps a photo eligible for grouping (G1 decision 3).
        #expect(time.isGroupable)
    }

    @Test func aZeroOffsetIsStillAnExplicitOffset() throws {
        let wall = try wallTime()
        let time = PhotoTime(captureWallTime: wall, utcOffsetSeconds: 0, in: .gmt)

        #expect(time.hasUTCOffset)
        #expect(abs(time.instant.timeIntervalSince(wall)) < 1e-6)
    }

    @Test func noOffsetIsReadInTheGivenZone() throws {
        let wall = try wallTime()
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let time = PhotoTime(captureWallTime: wall, utcOffsetSeconds: nil, in: newYork)

        #expect(time.source == .captureMetadata)
        // 12:34:56 in New York on 29 February 2024 is 17:34:56 UTC, never 12:34:56 UTC.
        #expect(!time.hasUTCOffset)
        #expect(abs(time.instant.timeIntervalSince(wall.addingTimeInterval(5 * 3_600))) < 1e-6)
        #expect(time.isGroupable)
    }

    @Test func theSubsecondSurvivesTheZoneMapping() throws {
        let wall = try wallTime()
        let first = PhotoTime(captureWallTime: wall, utcOffsetSeconds: nil, in: .gmt)
        let later = try wallTime(nanosecond: 507_000_000)
        let second = PhotoTime(captureWallTime: later, utcOffsetSeconds: nil, in: .gmt)

        // A burst's frames stay in order because the fraction is not rounded away.
        #expect(second.instant > first.instant)
        #expect(abs(first.instant.timeIntervalSince(wall)) < 1e-6)
    }

    @Test func aSummerZoneOffsetIsAppliedByTheCalendar() throws {
        let wall = try wallTime(month: 7, day: 1)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let time = PhotoTime(captureWallTime: wall, utcOffsetSeconds: nil, in: newYork)

        // New York is UTC−4 in July, so the instant is four hours later than the wall clock.
        #expect(abs(time.instant.timeIntervalSince(wall.addingTimeInterval(4 * 3_600))) < 1e-6)
    }
}
