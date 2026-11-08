import Testing

@testable import SpikeS3XMP

@Test func s3DescriptorMatchesThePlan() {
    #expect(SpikeS3XMP.descriptor.id == "S3")
    #expect(!SpikeS3XMP.descriptor.question.isEmpty)
}
