import Foundation
import SpikeSupport
import Testing

@testable import SpikeS7Duo

@Test func geometryChangesAreLoggedButIdenticalLayoutCallbacksAreNot() {
    var log = DuoLog(runID: "test")
    var sample = DuoSnapshot()
    sample.window = DuoRect(width: 390, height: 844)
    #expect(log.record(sample, reason: "initial") == true)
    #expect(log.record(sample, reason: "layout") == false)
    sample.window = DuoRect(width: 844, height: 390)
    sample.orientation = "landscapeLeft"
    #expect(log.record(sample, reason: "rotation") == true)
    sample.windowSafeArea.left = 47
    #expect(log.record(sample, reason: "safe area") == true)
    sample.horizontalSizeClass = "regular"
    #expect(log.record(sample, reason: "size class") == true)
    #expect(log.events.count == 4)
    #expect(log.events.first?.snapshot.window.width == 390)
}

@Test func unsupportedPendingAbsentAndClosedHingeRemainDistinct() {
    var sample = DuoSnapshot()
    var log = DuoLog()
    #expect(log.record(sample, reason: "old OS") == true)
    sample.hinge = DuoHinge(availability: .awaitingUpdate)
    #expect(log.record(sample, reason: "attached") == true)
    sample.hinge = DuoHinge(availability: .noHingeInHierarchy)
    #expect(log.record(sample, reason: "no hinge") == true)
    sample.hinge = DuoHinge(availability: .reported, status: "closed", angleRadians: 0)
    #expect(log.record(sample, reason: "closed") == true)
    sample.hinge = DuoHinge(availability: .reported, status: "partiallyOpen", angleRadians: .pi / 2)
    #expect(log.record(sample, reason: "half-fold") == true)
    #expect(log.events.count == 5)
    #expect(log.events[2].snapshot.tags["hinge.angle.radians"] == "unavailable")
    #expect(log.events[3].snapshot.tags["hinge.angle.radians"] == "0.0")
    #expect(log.events[4].snapshot.hinge.angleRadians == .pi / 2)
    #expect(sample.hinge.rectangleDescription == "not exposed by SDK 27.2")
}

@Test func journalPreservesEvidenceOfViewAndSceneRecreation() throws {
    var log = DuoLog(runID: "continuity")
    var sample = DuoSnapshot()
    sample.sceneID = "scene-A"
    sample.sceneStorageID = "restorable-A"
    sample.stateID = "view-A"
    sample.sceneStorageCounter = 1
    sample.stateCounter = 1
    log.record(sample, reason: "cover")
    let persisted = try JSONEncoder().encode(log)
    var restored = try JSONDecoder().decode(DuoLog.self, from: persisted)
    #expect(restored == log)
    // A recreated view can retain SceneStorage while losing State.
    sample.stateID = "view-B"
    sample.stateCounter = 0
    restored.record(sample, reason: "inner")
    #expect(restored.events[0].snapshot.stateCounter == 1)
    #expect(restored.events[1].snapshot.sceneStorageCounter == 1)
    #expect(restored.events[1].snapshot.stateCounter == 0)
    sample.sceneID = "scene-B"
    sample.sceneStorageID = "restorable-B"
    sample.sceneStorageCounter = 0
    #expect(restored.record(sample, reason: "new scene") == true)
    #expect(restored.events.count == 3)
    #expect(restored.runID == "continuity")
}

@Test func checkpointsCanRepeatWithoutGeometryChanges() {
    var log = DuoLog()
    let sample = DuoSnapshot()
    log.record(sample, reason: "cover")
    #expect(log.record(sample, reason: "checkpoint: half-fold", force: true) == true)
    #expect(log.events.count == 2)
}

@Test func reportRoundTripRetainsEveryEventWithOrderedTimestampedTags() throws {
    var sample = DuoSnapshot()
    sample.window = DuoRect(x: 2, y: 3, width: 900, height: 600)
    sample.scene = DuoRect(width: 902, height: 603)
    sample.swiftUISafeArea = DuoInsets(top: 20, left: 1, bottom: 34, right: 2)
    sample.stateCounter = 7
    var log = DuoLog(runID: "export-test")
    let date = Date(timeIntervalSince1970: 1_800_000_000.125)
    log.record(sample, reason: "rotation", at: date)
    log.record(sample, reason: "export", at: date.addingTimeInterval(0.25), force: true)
    let report = log.report(createdAt: Date(timeIntervalSince1970: 1_800_000_001))
    let decoded = try LabReport(jsonData: report.encoded())
    #expect(decoded == report)
    #expect(decoded.spike == "S7")
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.context["runID"] == "export-test")
    #expect(decoded.measurements.map(\.value) == [1, 2])
    #expect(decoded.measurements.allSatisfy { $0.name == "duo-event" && $0.unit == "count" })
    let tags = try #require(decoded.measurements.first?.tags)
    #expect(tags["timestamp"] == "2027-01-15T08:00:00.125Z")
    #expect(tags["window.xywh.pt"] == "2.0,3.0,900.0,600.0")
    #expect(tags["swiftUI.safeArea.tlbr.pt"] == "20.0,1.0,34.0,2.0")
    #expect(tags["stateCounter"] == "7")
    #expect(tags["hinge.status"] == "unavailable")
    let text = log.events[0].text
    #expect(text.hasPrefix("2027-01-15T08:00:00.125Z [rotation] "))
    #expect(text.contains("scene.xywh.pt=0.0,0.0,902.0,603.0"))
    #expect(text.range(of: "sceneID=")!.lowerBound < text.range(of: "stateCounter=")!.lowerBound)
}
