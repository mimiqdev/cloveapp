import Testing

@testable import ScanProbe

@Test func scanDescriptorMatchesThePlan() {
    #expect(ScanProbe.descriptor.id == "S6")
    #expect(!ScanProbe.descriptor.question.isEmpty)
}
