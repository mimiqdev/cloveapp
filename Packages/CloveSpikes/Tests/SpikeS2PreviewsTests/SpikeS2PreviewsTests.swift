import Testing

@testable import SpikeS2Previews

@Test func s2DescriptorMatchesThePlan() {
    #expect(SpikeS2Previews.descriptor.id == "S2")
    #expect(!SpikeS2Previews.descriptor.question.isEmpty)
}
