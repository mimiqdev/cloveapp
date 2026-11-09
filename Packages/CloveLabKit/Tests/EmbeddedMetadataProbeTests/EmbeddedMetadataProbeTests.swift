import Testing

@testable import EmbeddedMetadataProbe

@Test func embeddedMetadataDescriptorMatchesThePlan() {
    #expect(EmbeddedMetadataProbe.descriptor.id == "S4")
    #expect(!EmbeddedMetadataProbe.descriptor.question.isEmpty)
}
