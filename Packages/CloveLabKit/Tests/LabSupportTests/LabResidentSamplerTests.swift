import Foundation
import Testing

@testable import LabSupport

@Test func residentSamplerReportsProcessMemoryAndStops() {
    let sampler = LabResidentSampler()
    #expect(sampler.baseline > 0)
    #expect(sampler.peak >= sampler.baseline)
    #expect(sampler.finish() >= sampler.baseline)
    #expect(LabResidentSampler.currentBytes() > 0)
}
