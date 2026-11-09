import Foundation
import Testing

import CloveCore

@Test(arguments: ["cr3", "nef", "arw", "raf", "orf", "rw2", "dng"])
func rawClassificationUsesOneCaseInsensitiveBaseline(extensionValue: String) {
    #expect(PhotoFormat.rawExtensions.contains(extensionValue))
    #expect(PhotoFormat(pathExtension: extensionValue) == .raw)
    #expect(PhotoFormat(pathExtension: extensionValue.uppercased()) == .raw)
}

@Test func rawBaselineContainsExactlyTheRepositoryFormats() {
    #expect(PhotoFormat.rawExtensions == Set(["cr3", "nef", "arw", "raf", "orf", "rw2", "dng"]))
}

@Test(arguments: ["jpg", "jpeg", "JPG", "JpEg"])
func jpegClassification(extensionValue: String) {
    #expect(PhotoFormat(pathExtension: extensionValue) == .jpeg)
}

@Test(arguments: ["hif", "heif", "heic", "HIF", "HEIF", "HEIC"])
func heifClassification(extensionValue: String) {
    #expect(PhotoFormat(pathExtension: extensionValue) == .heif)
}

@Test(arguments: ["", ".arw", "mov", "png", "xmp", "ARW.xmp", "txt"])
func unsupportedExtensionsAreNotImages(extensionValue: String) {
    #expect(PhotoFormat(pathExtension: extensionValue) == nil)
}

@Test func photoFileRetainsItsURLAndRequiresFileScheme() throws {
    let url = URL(fileURLWithPath: "/not-read/Some Folder/MiXeD.ARW")
    let file = try #require(PhotoFile(url: url))
    #expect(file.url == url)
    #expect(file.url.lastPathComponent == "MiXeD.ARW")
    #expect(file.format == .raw)
    #expect(PhotoFile(url: try #require(URL(string: "https://example.com/image.ARW"))) == nil)
    #expect(PhotoFile(url: URL(fileURLWithPath: "/not-read/image.txt")) == nil)
}
