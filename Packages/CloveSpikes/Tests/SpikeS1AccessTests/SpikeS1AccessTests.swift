import Testing

@testable import SpikeS1Access

@Test func s1DescriptorMatchesThePlan() {
    #expect(SpikeS1Access.descriptor.id == "S1")
    #expect(!SpikeS1Access.descriptor.question.isEmpty)
}
