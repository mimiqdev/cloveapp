import Testing

@testable import SpikeS4Metadata

@Test func s4DescriptorMatchesThePlan() {
    #expect(SpikeS4Metadata.descriptor.id == "S4")
    #expect(!SpikeS4Metadata.descriptor.question.isEmpty)
}
