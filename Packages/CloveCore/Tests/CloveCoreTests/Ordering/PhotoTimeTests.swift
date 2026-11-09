import Foundation
import Testing

import CloveCore

@Test func captureTimeRecordsWhetherAnOffsetWasPresent() {
    let withOffset = PhotoTime(captureTime: orderingBase, hasUTCOffset: true)
    #expect(withOffset.source == .captureMetadata)
    #expect(withOffset.hasUTCOffset)
    #expect(withOffset.isGroupable)

    let wallTime = PhotoTime(captureTime: orderingBase, hasUTCOffset: false)
    #expect(wallTime.source == .captureMetadata)
    #expect(!wallTime.hasUTCOffset)
    #expect(wallTime.isGroupable)
}

@Test func fileTimesAreSortingFallbacksOnly() {
    let creation = PhotoTime(fileCreation: orderingBase)
    #expect(creation.source == .fileCreation)
    #expect(!creation.hasUTCOffset)
    #expect(!creation.isGroupable)

    let modification = PhotoTime(fileModification: orderingBase)
    #expect(modification.source == .fileModification)
    #expect(!modification.hasUTCOffset)
    #expect(!modification.isGroupable)
}

@Test func subsecondInstantsSurviveTheValue() {
    let instant = seconds(0.125_001)
    #expect(PhotoTime(captureTime: instant, hasUTCOffset: true).instant == instant)
    #expect(PhotoTime(captureTime: instant, hasUTCOffset: false).instant == instant)
    #expect(PhotoTime(fileCreation: instant).instant == instant)
    #expect(PhotoTime(fileModification: instant).instant == instant)
}

@Test func timeStatesReportTheTimeAndGroupingEligibility() {
    #expect(PhotoTimeState.pending.time == nil)
    #expect(PhotoTimeState.pending.isPending)
    #expect(!PhotoTimeState.pending.isGroupable)

    #expect(PhotoTimeState.unavailable.time == nil)
    #expect(!PhotoTimeState.unavailable.isPending)
    #expect(!PhotoTimeState.unavailable.isGroupable)

    let fallback = PhotoTime(fileCreation: orderingBase)
    #expect(PhotoTimeState.known(fallback).time == fallback)
    #expect(!PhotoTimeState.known(fallback).isPending)
    #expect(!PhotoTimeState.known(fallback).isGroupable)

    let wallClock = PhotoTime(captureTime: orderingBase, hasUTCOffset: false)
    #expect(PhotoTimeState.known(wallClock).isGroupable)
}
