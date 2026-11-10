import Testing

import CloveCore

@Test func defaultRejectsFolderNameIsUnderscoredRejected() {
    #expect(RejectsFolderName.defaultFolderName.rawValue == "_Rejected")
    #expect(AppSettings().rejectsFolderName == .defaultFolderName)
}

@Test(arguments: ["_Rejected", "Rejected", "2024 rejects", "审片", "Keep", "a_b-c"])
func validNamesAreKeptExactly(name: String) throws {
    let validated = try RejectsFolderName.validated(name)
    #expect(validated.rawValue == name)
    #expect(RejectsFolderName(rawValue: name) == validated)
}

@Test func invalidNamesAreRefusedNotChanged() {
    let cases: [(name: String, reason: RejectsFolderNameError)] = [
        ("", .empty),
        ("Rejected/2024", .pathSeparator),
        ("/", .pathSeparator),
        (".", .relativeComponent),
        ("..", .relativeComponent),
        (".Rejected", .hidden),
        ("Rejected\0", .controlCharacter),
        ("Rejected\n2024", .controlCharacter),
    ]
    for (name, reason) in cases {
        #expect(RejectsFolderName(rawValue: name) == nil)
        #expect(validationError(name) == reason)
    }
}

@Test func namesAreNotTrimmedOrCorrected() throws {
    let padded = " Keep "
    let validated = try RejectsFolderName.validated(padded)
    #expect(validated.rawValue == padded)
    #expect(RejectsFolderName(rawValue: padded)?.rawValue == padded)
}

@Test func lengthLimitCountsUTF8Bytes() throws {
    let longestASCII = String(repeating: "a", count: RejectsFolderName.maximumUTF8Length)
    #expect(RejectsFolderName(rawValue: longestASCII) != nil)

    let tooLongASCII = longestASCII + "a"
    #expect(RejectsFolderName(rawValue: tooLongASCII) == nil)
    #expect(validationError(tooLongASCII) == .tooLong)

    let sixteenCameraGlyphs = String(repeating: "📷", count: 16)
    #expect(sixteenCameraGlyphs.utf8.count == RejectsFolderName.maximumUTF8Length)
    #expect(RejectsFolderName(rawValue: sixteenCameraGlyphs) != nil)

    let seventeenCameraGlyphs = sixteenCameraGlyphs + "📷"
    #expect(RejectsFolderName(rawValue: seventeenCameraGlyphs) == nil)
    #expect(validationError(seventeenCameraGlyphs) == .tooLong)
}

@Test func everyRefusalExplainsItselfInPlainText() {
    let cases: [(error: RejectsFolderNameError, message: String)] = [
        (.empty, "Enter a folder name."),
        (.pathSeparator, "Use one folder name, without a slash."),
        (.relativeComponent, "\".\" and \"..\" can't name a folder here."),
        (.hidden, "A folder name can't start with a dot."),
        (.controlCharacter, "A folder name can't contain invisible control characters."),
        (.tooLong, "Use a shorter name: at most 64 bytes."),
    ]
    for (error, message) in cases {
        #expect(error.message == message)
        #expect(!error.message.isEmpty)
    }
}

@Test func refusedNamesCarryTheirExplanation() {
    let cases: [(name: String, reason: RejectsFolderNameError)] = [
        ("", .empty),
        ("Rejected/2024", .pathSeparator),
        ("..", .relativeComponent),
        (".Rejected", .hidden),
        ("Rejected\n2024", .controlCharacter),
        (String(repeating: "a", count: RejectsFolderName.maximumUTF8Length + 1), .tooLong),
    ]
    for (name, reason) in cases {
        do {
            _ = try RejectsFolderName.validated(name)
            Issue.record("the name \(name) was accepted")
        } catch {
            #expect(error == reason)
            #expect(error.message == reason.message)
        }
    }
}

private func validationError(_ name: String) -> RejectsFolderNameError? {
    do {
        _ = try RejectsFolderName.validated(name)
        return nil
    } catch {
        return error
    }
}
