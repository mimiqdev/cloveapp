import Testing

@testable import FoldStateProbe

@Test func foldStateDescriptorMatchesThePlan() {
    #expect(FoldStateProbe.descriptor.id == "S7")
    #expect(!FoldStateProbe.descriptor.question.isEmpty)
}
