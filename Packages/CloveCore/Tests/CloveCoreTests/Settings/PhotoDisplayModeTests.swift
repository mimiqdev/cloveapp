import Testing

import CloveCore

struct PhotoDisplayModeTests {
    let fiveGiB: UInt64 = 5 * 1024 * 1024 * 1024

    @Test func reportedMemoryBoundary() {
        #expect(PhotoDisplayDefault.mode(physicalMemory: fiveGiB - 1) == .cameraPreviewFirst)
        #expect(PhotoDisplayDefault.mode(physicalMemory: fiveGiB) == .rawFirst)
        // Reported memory for nominal 4 GB and 6 GB phones falls on opposite sides.
        #expect(
            PhotoDisplayDefault.mode(physicalMemory: 37 * 1024 * 1024 * 1024 / 10)
                == .cameraPreviewFirst)
        #expect(PhotoDisplayDefault.mode(physicalMemory: 55 * 1024 * 1024 * 1024 / 10) == .rawFirst)
    }

    @Test func explicitChoiceWinsAndResetRemovesStoredChoice() {
        let storage = InMemorySettingsStorage()
        let persistence = SettingsPersistence(storage: storage)
        var settings = AppSettings()
        settings.photoDisplayMode = .rawFirst
        #expect(persistence.saveVerified(settings))
        #expect(
            PhotoDisplayDefault.mode(
                physicalMemory: 1, choice: persistence.load().photoDisplayMode) == .rawFirst)
        settings.photoDisplayMode = .cameraPreviewFirst
        persistence.save(settings)
        #expect(
            PhotoDisplayDefault.mode(
                physicalMemory: fiveGiB, choice: persistence.load().photoDisplayMode)
                == .cameraPreviewFirst)
        #expect(persistence.saveVerified(AppSettings()))
        #expect(storage.string(forKey: "detail.photoDisplayMode") == nil)
        #expect(
            PhotoDisplayDefault.mode(physicalMemory: 1, choice: persistence.load().photoDisplayMode)
                == .cameraPreviewFirst)
    }
}
