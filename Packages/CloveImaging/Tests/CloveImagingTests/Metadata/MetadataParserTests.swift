import Foundation
import Testing

@testable import CloveImaging

private func parseTime(
    _ date: Any = "2024:02:29 12:34:56", subseconds: Any? = nil, offset: Any? = nil
) -> ImageMetadata {
    var exif: [String: Any] = ["DateTimeOriginal": date]
    exif["SubsecTimeOriginal"] = subseconds
    exif["OffsetTimeOriginal"] = offset
    return MetadataParser.parse(
        properties: ["{Exif}": exif], creationDate: nil, modificationDate: nil)
}

@Test(arguments: [
    "0", "00", "7", "06", "089", "000001", "123456789", "123456789123", " 007 ", "007   ",
])
func captureFractionRetainsDigits(_ value: String) throws {
    let digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let metadata = parseTime(subseconds: value)
    let capture = try #require(metadata.captureTime.value)
    let whole = try #require(parseTime().captureTime.value)
    #expect(
        abs(capture.wallTime.timeIntervalSince(whole.wallTime) - Double("0." + digits)!) < 0.000001)
    #expect(
        metadata.subseconds == .value(digits, source: .imageProperty("{Exif}.SubsecTimeOriginal")))
    #expect(capture.timestamp == .cameraWallTime(capture.wallTime))
    #expect(metadata.utcOffset == .missing)
    #expect(metadata.time == .captureMetadata(capture))
}

@Test(arguments: ["+00:00", "+05:30", "-03:45", "+23:59"])
func captureOffsetProducesAbsoluteTime(_ offset: String) throws {
    let metadata = parseTime(subseconds: "007", offset: offset)
    let capture = try #require(metadata.captureTime.value)
    let seconds = try #require(metadata.utcOffset.value)
    #expect(capture.utcOffsetSeconds == seconds)
    #expect(capture.timestamp == .utc(capture.wallTime.addingTimeInterval(-Double(seconds))))
    #expect(metadata.utcOffset.source == .imageProperty("{Exif}.OffsetTimeOriginal"))
    if offset == "+05:30" { #expect(seconds == 19800) }
    if offset == "-03:45" { #expect(seconds == -13500) }
}

@Test(arguments: [
    "2023:02:29 12:00:00", "2024:13:01 12:00:00", "2024:01:01 24:00:00", "2024:1:01 12:00:00",
    "2024-01-01T12:00:00Z", "", "0000:01:01 00:00:00",
])
func malformedCaptureIsExplicit(_ value: String) {
    let metadata = parseTime(value)
    #expect(
        metadata.captureTime
            == .invalid(rawValue: value, source: .imageProperty("{Exif}.DateTimeOriginal")))
    #expect(metadata.time == .unavailable)
}

@Test(arguments: ["1.2", "-1", "１２", "7x"])
func malformedFractionIsExplicit(_ value: String) throws {
    let metadata = parseTime(subseconds: value, offset: "+05:30")
    #expect(
        metadata.subseconds
            == .invalid(rawValue: value, source: .imageProperty("{Exif}.SubsecTimeOriginal")))
    let capture = try #require(metadata.captureTime.value)
    #expect(metadata.captureTime == parseTime(offset: "+05:30").captureTime)
    #expect(capture.utcOffsetSeconds == 19800)
    #expect(metadata.time == .captureMetadata(capture))
}

@Test(arguments: ["Z", "+24:00", "+00:60", "05:30", "+5:30", "+０５:30"])
func malformedOffsetIsExplicit(_ value: String) throws {
    let metadata = parseTime(subseconds: "007", offset: value)
    #expect(
        metadata.utcOffset
            == .invalid(rawValue: value, source: .imageProperty("{Exif}.OffsetTimeOriginal")))
    let capture = try #require(metadata.captureTime.value)
    #expect(metadata.captureTime == parseTime(subseconds: "007").captureTime)
    #expect(capture.utcOffsetSeconds == nil)
    #expect(capture.timestamp == .cameraWallTime(capture.wallTime))
    #expect(metadata.time == .captureMetadata(capture))
}

@Test(arguments: ["", " ", "     ", "   :  ", ":", " : : ", "\t\n"])
func unknownTimeDetailsAreMissingAndKeepCapture(_ value: String) throws {
    let metadata = parseTime(subseconds: value, offset: value)
    let capture = try #require(metadata.captureTime.value)
    #expect(metadata.subseconds == .missing)
    #expect(metadata.utcOffset == .missing)
    #expect(metadata.captureTime == parseTime().captureTime)
    #expect(capture.utcOffsetSeconds == nil)
    #expect(capture.timestamp == .cameraWallTime(capture.wallTime))
    #expect(metadata.time == .captureMetadata(capture))
}

@Test(arguments: ["", "   :  ", "1.2", "7x", "+24:00", "+5:30"])
func unusableTimeDetailsDoNotSelectFileDateFallback(_ value: String) throws {
    let metadata = MetadataParser.parse(
        properties: [
            "{Exif}": [
                "DateTimeOriginal": "2024:02:29 12:34:56",
                "SubsecTimeOriginal": value, "OffsetTimeOriginal": value,
            ]
        ], creationDate: Date(timeIntervalSince1970: 100),
        modificationDate: Date(timeIntervalSince1970: 200))
    let capture = try #require(metadata.captureTime.value)
    #expect(metadata.captureTime == parseTime().captureTime)
    #expect(metadata.time == .captureMetadata(capture))
}

@Test func metadataIdentityPreferenceAndMissingStates() {
    let metadata = MetadataParser.parse(
        properties: [
            "{Exif}": ["BodySerialNumber": " exif ", "LensSerialNumber": "lens"],
            "{ExifAux}": ["SerialNumber": "aux"],
            "{MakerSony}": ["SerialNumber": "maker"],
            "{TIFF}": ["Model": " ILCE-1M2 \n", "DateTime": "2024:01:01 12:00:00"],
        ], creationDate: nil, modificationDate: nil)
    #expect(metadata.model == .value("ILCE-1M2", source: .imageProperty("{TIFF}.Model")))
    #expect(
        metadata.bodySerial == .value("exif", source: .imageProperty("{Exif}.BodySerialNumber")))
    #expect(metadata.captureTime == .missing)
    #expect(metadata.subseconds == .missing)
    #expect(metadata.utcOffset == .missing)
    #expect(metadata.fileCreationTime == .missing)
    #expect(metadata.time == .unavailable)
    let noBody = MetadataParser.parse(
        properties: ["{Exif}": ["LensSerialNumber": "lens"]], creationDate: nil,
        modificationDate: nil)
    #expect(noBody.bodySerial == .missing)
    #expect(noBody.model == .missing)
}

@Test(arguments: [
    "{ExifAux}.SerialNumber", "{MakerCanon}.SerialNumber", "{MakerNikon}.SerialNumber",
    "{MakerNikon}.SerialNO", "{MakerFuji}.SerialNumber", "{MakerOlympus}.SerialNumber",
    "{MakerPanasonic}.SerialNumber", "{MakerSony}.SerialNumber", "{MakerPentax}.SerialNumber",
])
func bodySerialFallbackPaths(_ path: String) {
    let parts = path.split(separator: ".").map(String.init)
    let metadata = MetadataParser.parse(
        properties: ["{Exif}": ["BodySerialNumber": " "], parts[0]: [parts[1]: 12345]],
        creationDate: nil, modificationDate: nil)
    #expect(metadata.bodySerial == .value("12345", source: .imageProperty(path)))
}

@Test func unusableCaptureFallsBackWithoutLosingItsInvalidState() {
    let creation = Date(timeIntervalSince1970: 100)
    let modification = Date(timeIntervalSince1970: 200)
    let properties: [String: Any] = ["{Exif}": ["DateTimeOriginal": "not a capture date"]]
    let metadata = MetadataParser.parse(
        properties: properties, creationDate: creation, modificationDate: modification)
    #expect(metadata.time == .fileCreation(creation))
    #expect(
        metadata.captureTime
            == .invalid(
                rawValue: "not a capture date", source: .imageProperty("{Exif}.DateTimeOriginal")))
    let noCreation = MetadataParser.parse(
        properties: properties, creationDate: nil, modificationDate: modification)
    #expect(noCreation.time == .fileModification(modification))
}

@Test func wrongPropertyTypesAndInvalidFileDates() {
    let metadata = MetadataParser.parse(
        properties: ["{Exif}": ["DateTimeOriginal": ["bad"], "BodySerialNumber": true]],
        creationDate: Date(timeIntervalSinceReferenceDate: .infinity),
        modificationDate: Date(timeIntervalSince1970: 100))
    #expect(metadata.captureTime.value == nil)
    #expect(metadata.captureTime.source == .imageProperty("{Exif}.DateTimeOriginal"))
    #expect(metadata.bodySerial.value == nil)
    #expect(metadata.time == .fileModification(Date(timeIntervalSince1970: 100)))
}

@Test func lensExtractionTrimsAndFallsBackToExifAux() {
    let exifLens = MetadataParser.parse(
        properties: [
            "{Exif}": ["LensModel": "  FE 35mm F1.4 GM  "],
            "{ExifAux}": ["LensModel": "Auxiliary Lens"],
        ], creationDate: nil, modificationDate: nil)
    #expect(exifLens.lens == .value("FE 35mm F1.4 GM", source: .imageProperty("{Exif}.LensModel")))

    let auxFallback = MetadataParser.parse(
        properties: [
            "{Exif}": ["LensModel": "   "],
            "{ExifAux}": ["LensModel": " RF 50mm F1.2L USM "],
        ], creationDate: nil, modificationDate: nil)
    #expect(
        auxFallback.lens
            == .value("RF 50mm F1.2L USM", source: .imageProperty("{ExifAux}.LensModel")))

    let invalidLens = MetadataParser.parse(
        properties: ["{Exif}": ["LensModel": 35]], creationDate: nil, modificationDate: nil)
    #expect(invalidLens.lens.value == nil)
    #expect(invalidLens.lens.source == .imageProperty("{Exif}.LensModel"))

    let missingLens = MetadataParser.parse(
        properties: [:], creationDate: nil, modificationDate: nil)
    #expect(missingLens.lens == .missing)
}

@Test func focalLengthPrefers35mmEquivalentAndFallsBackToActual() {
    let both = MetadataParser.parse(
        properties: ["{Exif}": ["FocalLength": 23.0, "FocalLenIn35mmFilm": 35]],
        creationDate: nil, modificationDate: nil)
    #expect(
        both.focalLengthMillimetres
            == .value(23.0, source: .imageProperty("{Exif}.FocalLength")))
    #expect(
        both.focalLength35mmEquivalent
            == .value(35.0, source: .imageProperty("{Exif}.FocalLenIn35mmFilm")))
    #expect(both.effectiveFocalLengthMillimetres == 35.0)

    // Many cameras write 0 for unknown 35mm equivalent; effective focal length must fall back.
    let zeroEquivalent = MetadataParser.parse(
        properties: ["{Exif}": ["FocalLength": 85.0, "FocalLenIn35mmFilm": 0]],
        creationDate: nil, modificationDate: nil)
    #expect(zeroEquivalent.focalLength35mmEquivalent.value == nil)
    #expect(zeroEquivalent.focalLengthMillimetres.value == 85.0)
    #expect(zeroEquivalent.effectiveFocalLengthMillimetres == 85.0)

    let actualOnly = MetadataParser.parse(
        properties: ["{Exif}": ["FocalLength": 200.5]],
        creationDate: nil, modificationDate: nil)
    #expect(actualOnly.focalLength35mmEquivalent == .missing)
    #expect(actualOnly.effectiveFocalLengthMillimetres == 200.5)

    let invalidValues = MetadataParser.parse(
        properties: [
            "{Exif}": [
                "FocalLength": Double.infinity,
                "FocalLenIn35mmFilm": true,
            ]
        ], creationDate: nil, modificationDate: nil)
    #expect(invalidValues.focalLengthMillimetres.value == nil)
    #expect(invalidValues.focalLength35mmEquivalent.value == nil)
    #expect(invalidValues.effectiveFocalLengthMillimetres == nil)
}
