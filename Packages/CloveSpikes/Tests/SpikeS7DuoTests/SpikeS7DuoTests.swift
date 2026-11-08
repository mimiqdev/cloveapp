import Testing

@testable import SpikeS7Duo

@Test func s7DescriptorMatchesThePlan() {
    #expect(SpikeS7Duo.descriptor.id == "S7")
    #expect(!SpikeS7Duo.descriptor.question.isEmpty)
}
