import Testing

import CloveCore

struct PhotoDisplayModeTests {
    let sixGiB: UInt64 = 6 * 1024 * 1024 * 1024

    @Test func memoryAndSpeedBoundaries() {
        #expect(PhotoDisplayDefault.mode(physicalMemory: sixGiB - 1) == .cameraPreviewFirst)
        #expect(PhotoDisplayDefault.mode(physicalMemory: sixGiB) == .rawFirst)
        #expect(
            PhotoDisplayDefault.mode(
                physicalMemory: sixGiB,
                measurement: RAWRenderMeasurement(samples: [100, 900, 701, 800, 200]))
                == .cameraPreviewFirst)
        #expect(
            PhotoDisplayDefault.mode(
                physicalMemory: sixGiB,
                measurement: RAWRenderMeasurement(samples: [100, 900, 700, 800, 200])) == .rawFirst)
    }

    @Test func speedWaitsForFiveAndNeverRemeasures() {
        var measurement = RAWRenderMeasurement(samples: [900, 900, 900, 900])
        #expect(measurement.medianMilliseconds == nil)
        #expect(
            PhotoDisplayDefault.mode(physicalMemory: sixGiB, measurement: measurement) == .rawFirst)
        measurement.record(milliseconds: 900)
        measurement.record(milliseconds: 1)
        #expect(measurement.samples.count == 5)
        #expect(measurement.medianMilliseconds == 900)
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
                physicalMemory: sixGiB, choice: persistence.load().photoDisplayMode)
                == .cameraPreviewFirst)
        #expect(persistence.saveVerified(AppSettings()))
        #expect(storage.string(forKey: "detail.photoDisplayMode") == nil)
        #expect(
            PhotoDisplayDefault.mode(physicalMemory: 1, choice: persistence.load().photoDisplayMode)
                == .cameraPreviewFirst)
    }

    @Test func invalidSamplesCannotDecideSpeed() {
        let measurement = RAWRenderMeasurement(samples: [.nan, .infinity, -1, 800])
        #expect(measurement.samples == [800])
        #expect(measurement.medianMilliseconds == nil)
    }
}
