import Testing

@testable import GroupingProbe

@Test func groupingDescriptorMatchesThePlan() {
    #expect(GroupingProbe.descriptor.id == "S5")
    #expect(!GroupingProbe.descriptor.question.isEmpty)
}
