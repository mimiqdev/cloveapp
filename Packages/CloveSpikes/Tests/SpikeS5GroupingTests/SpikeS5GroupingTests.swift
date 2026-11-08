import Testing

@testable import SpikeS5Grouping

@Test func s5DescriptorMatchesThePlan() {
    #expect(SpikeS5Grouping.descriptor.id == "S5")
    #expect(!SpikeS5Grouping.descriptor.question.isEmpty)
}
