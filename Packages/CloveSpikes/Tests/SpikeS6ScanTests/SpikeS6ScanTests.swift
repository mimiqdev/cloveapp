import Testing

@testable import SpikeS6Scan

@Test func s6DescriptorMatchesThePlan() {
    #expect(SpikeS6Scan.descriptor.id == "S6")
    #expect(!SpikeS6Scan.descriptor.question.isEmpty)
}
