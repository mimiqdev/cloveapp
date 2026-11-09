import Testing

@testable import FolderAccessProbe

@Test func folderAccessDescriptorMatchesThePlan() {
    #expect(FolderAccessProbe.descriptor.id == "S1")
    #expect(!FolderAccessProbe.descriptor.question.isEmpty)
}
