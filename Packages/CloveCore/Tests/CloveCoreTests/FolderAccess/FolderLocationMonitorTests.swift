import Foundation
import Testing

import CloveCore

private func makeVolumeLayout() throws -> (volume: URL, folder: URL) {
    let volume = try makeTemporaryFolder()
    let folder = volume.appendingPathComponent("DCIM", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return (volume, folder)
}

@Test func deletingTheFolderReportsOneLossAndStopsTheWatch() async throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    let monitor = FolderLocationMonitor(
        rootURL: folder, mediaType: .internalVolume, presenting: presenter)
    await monitor.start { recorder.record($0) }
    #expect(await monitor.isWatching)
    #expect(presenter.isPresenting)

    try FileManager.default.removeItem(at: folder)
    presenter.notifyChange()
    try await waitUntil { recorder.losses.count == 1 }
    #expect(recorder.losses.count == 1)
    #expect(recorder.losses.first?.reason == .locationUnavailable)
    #expect(presenter.stopCount == 1)
    #expect(await monitor.isWatching == false)

    presenter.notifyChange()
    try await Task.sleep(for: .milliseconds(50))
    #expect(recorder.losses.count == 1)
    await monitor.stop()
    #expect(presenter.stopCount == 1)
}

@Test func thePollingTimerFindsALostLocationAndStopsItself() async throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    let monitor = FolderLocationMonitor(
        rootURL: folder, mediaType: .cloudProvider, pollInterval: .milliseconds(20),
        presenting: presenter)
    await monitor.start { recorder.record($0) }
    try FileManager.default.removeItem(at: folder)

    try await waitUntil { recorder.losses.count == 1 }
    #expect(recorder.losses.count == 1)
    #expect(recorder.losses.first?.reason == .locationUnavailable)
    #expect(presenter.stopCount == 1)
    #expect(await monitor.isWatching == false)
}

@Test func aLocalFolderWithAnExternalHintIsNotADriveDisconnect() async throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    // No volume root supplied: the monitor reads this folder's real local volume, which stays up.
    let monitor = FolderLocationMonitor(
        rootURL: folder, mediaType: .externalDrive, presenting: presenter)
    await monitor.start { recorder.record($0) }
    try FileManager.default.removeItem(at: folder)
    presenter.notifyChange()

    try await waitUntil { recorder.losses.count == 1 }
    #expect(recorder.losses.first?.reason == .locationUnavailable)
    await monitor.stop()
}

@Test func aMissingExternalVolumeRootIsADriveDisconnect() async throws {
    let layout = try makeVolumeLayout()
    defer { try? FileManager.default.removeItem(at: layout.volume) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    let monitor = FolderLocationMonitor(
        rootURL: layout.folder, mediaType: .externalDrive, volumeRootURL: layout.volume,
        presenting: presenter)
    await monitor.start { recorder.record($0) }
    try FileManager.default.removeItem(at: layout.volume)
    presenter.notifyChange()

    try await waitUntil { recorder.losses.count == 1 }
    #expect(recorder.losses.count == 1)
    #expect(recorder.losses.first?.reason == .externalVolumeDisconnected)
    await monitor.stop()
}

@Test func aMissingFolderOnAReachableVolumeIsUnavailable() async throws {
    let layout = try makeVolumeLayout()
    defer { try? FileManager.default.removeItem(at: layout.volume) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    let monitor = FolderLocationMonitor(
        rootURL: layout.folder, mediaType: .externalDrive, volumeRootURL: layout.volume,
        presenting: presenter)
    await monitor.start { recorder.record($0) }
    try FileManager.default.removeItem(at: layout.folder)
    presenter.notifyChange()

    try await waitUntil { recorder.losses.count == 1 }
    #expect(recorder.losses.first?.reason == .locationUnavailable)
    await monitor.stop()
}

@Test func aLostProviderVolumeIsUnavailableRatherThanADisconnect() async throws {
    let layout = try makeVolumeLayout()
    defer { try? FileManager.default.removeItem(at: layout.volume) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    let monitor = FolderLocationMonitor(
        rootURL: layout.folder, mediaType: .cloudProvider, volumeRootURL: layout.volume,
        presenting: presenter)
    await monitor.start { recorder.record($0) }
    try FileManager.default.removeItem(at: layout.volume)
    presenter.notifyChange()

    try await waitUntil { recorder.losses.count == 1 }
    #expect(recorder.losses.first?.reason == .locationUnavailable)
    await monitor.stop()
}

@Test func stoppingRemovesThePresenterAndIgnoresFurtherChecks() async throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    let monitor = FolderLocationMonitor(
        rootURL: folder, mediaType: .internalVolume, presenting: presenter)
    await monitor.start { recorder.record($0) }
    await monitor.stop()
    #expect(presenter.stopCount == 1)
    #expect(presenter.isPresenting == false)
    #expect(await monitor.isWatching == false)

    try FileManager.default.removeItem(at: folder)
    await monitor.checkNow()
    #expect(recorder.losses.isEmpty)
}

@Test func startingAgainReplacesTheEarlierWatch() async throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let presenter = ManualFolderChangePresenter()
    let recorder = LossRecorder()
    let monitor = FolderLocationMonitor(
        rootURL: folder, mediaType: .internalVolume, presenting: presenter)
    await monitor.start { recorder.record($0) }
    await monitor.start { recorder.record($0) }
    #expect(presenter.startCount == 2)
    #expect(presenter.stopCount == 1)

    try FileManager.default.removeItem(at: folder)
    presenter.notifyChange()
    try await waitUntil { recorder.losses.count == 1 }
    #expect(recorder.losses.count == 1)
}
