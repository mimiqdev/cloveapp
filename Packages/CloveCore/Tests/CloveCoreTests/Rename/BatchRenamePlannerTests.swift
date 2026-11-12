import Foundation
import Testing

@testable import CloveCore

@Suite("Batch rename planning")
struct BatchRenamePlannerTests {
    @Test func preservesOrderExtensionsAndIncludesSidecarWrittenAfterScan() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let second = try fixture.item("second", formats: [.raw, .heif])
        let first = try fixture.item("first", path: "sub")
        try fixture.folder.write("late packet", to: "second.xmp")
        let plan = fixture.plan([second, first], template: RenameTemplate(prefix: "Trip_"))
        #expect(plan.canRename)
        #expect(plan.rows.map(\.oldStem) == ["second", "first"])
        #expect(plan.rows.map(\.newStem) == ["Trip_001", "Trip_002"])
        #expect(
            plan.rows[0].files.map { $0.destination.lastPathComponent }
                == ["Trip_001.ARW", "Trip_001.HIF", "Trip_001.xmp"])
        #expect(plan.rows[1].destinationRelativeFolder == "sub")
        #expect(!plan.requiresTemporaryNames)
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.fileSystem.count(of: .createDirectory) == 0)
    }

    @Test func swapUsesTemporaryNamesButCaseOnlyRenameIsNoOp() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let one = try fixture.item("Shot_001")
        let two = try fixture.item("Shot_002")
        let template = RenameTemplate(prefix: "shot_")
        let swap = fixture.plan([two, one], template: template)
        #expect(swap.canRename)
        #expect(swap.requiresTemporaryNames)
        let unchanged = fixture.plan([one, two], template: template)
        #expect(unchanged.rows.allSatisfy { $0.isNoOp })
        #expect(!unchanged.requiresTemporaryNames)
    }

    @Test func outsideTargetIsAReplacementWithoutAnyWriteDuringPlanning() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("source")
        try fixture.folder.write("outside", to: "001.arw")
        let plan = fixture.plan([item])
        #expect(plan.canRename)
        #expect(plan.replacementCount == 1)
        let replacement = try #require(plan.rows[0].replacement)
        #expect(replacement.stem == "001")
        #expect(PhotoFilePath.matches(replacement.files[0].source, fixture.folder.file("001.arw")))
        #expect(
            PhotoFilePath.matches(
                replacement.files[0].destination, fixture.folder.file("_Rejected/001.arw")))
        #expect(fixture.fileSystem.count(of: .move) == 0)
        #expect(fixture.fileSystem.count(of: .createDirectory) == 0)
        #expect(fixture.folder.contents(of: "001.arw") == Data("outside".utf8))
    }

    @Test func outsideCompanionCannotBeAccidentallyPaired() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("source")
        try fixture.folder.write("outside JPEG", to: "001.JPG")
        let plan = fixture.plan([item])
        #expect(plan.canRename)
        #expect(plan.replacementCount == 1)
        #expect(plan.rows[0].replacement?.files.first?.source.lastPathComponent == "001.JPG")
    }

    @Test(arguments: [
        "bad/", "bad:", "bad\\", "bad*", "bad?", "bad\"", "bad<", "bad>", "bad|", "\u{0}", "\u{7f}",
        ".bad", " bad",
    ])
    func invalidCharactersAreProblems(prefix: String) throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("source")
        let plan = fixture.plan([item], template: RenameTemplate(prefix: prefix))
        #expect(!plan.canRename)
        #expect(plan.rows[0].problems.contains(.invalidName(prefix + "001")))
    }

    @Test(arguments: ["bad.", "bad ", ".", "..", "", "nested/folder", "bad:"])
    func invalidDestinationFolderIsAProblem(name: String) throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("source")
        let plan = fixture.plan([item], destination: .folder(name))
        #expect(!plan.canRename)
        #expect(plan.rows[0].problems.contains(.invalidName(name)))
        #expect(fixture.fileSystem.count(of: .createDirectory) == 0)
    }

    @Test func checksFullFilenameByteLengthAndAllRows() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("first")
        let second = try fixture.item("second")
        let prefix = String(repeating: "é", count: 125)
        let plan = fixture.plan([first, second], template: RenameTemplate(prefix: prefix))
        #expect(
            plan.rows.allSatisfy {
                $0.problems.contains(.nameTooLong(prefix + "001.ARW"))
                    || $0.problems.contains(.nameTooLong(prefix + "002.ARW"))
            })
        #expect(!plan.canRename)
        #expect(BatchRenamePlanner.nameProblems("trailing.") == [.invalidName("trailing.")])
        #expect(BatchRenamePlanner.nameProblems("trailing ") == [.invalidName("trailing ")])
    }

    @Test func duplicateTargetsCompareCaseInsensitivelyAndOnlyWithinDestination() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("first")
        let second = try fixture.item("second")
        let original = fixture.plan([first, second]).rows
        func row(_ index: Int, _ stem: String) -> BatchRenameRow {
            let old = original[index]
            return BatchRenameRow(
                item: old.item, oldStem: old.oldStem, newStem: stem,
                destinationRelativeFolder: "",
                files: [
                    RenameFile(
                        source: old.files[0].source,
                        destination: fixture.folder.file(stem + ".ARW"))
                ],
                problems: [], isNoOp: false)
        }
        let rows = BatchRenamePlanner(fileSystem: fixture.fileSystem)
            .checkingDuplicateTargets([row(0, "Name"), row(1, "name")])
        #expect(
            rows.allSatisfy { row in
                row.problems.contains(.duplicateTarget(row.files[0].destination))
            })
    }

    @Test func overflowInvalidDigitsAndRepeatedSourcesRefuseWithoutTrapping() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let first = try fixture.item("first")
        let second = try fixture.item("second")
        let overflow = fixture.plan([first, second], template: RenameTemplate(sequenceStart: .max))
        #expect(!overflow.canRename)
        #expect(overflow.rows[1].problems.contains(.sequenceOverflow))
        #expect(!fixture.plan([first], template: RenameTemplate(digits: .max)).canRename)
        #expect(!fixture.plan([first], template: RenameTemplate(sequenceStart: -1)).canRename)
        #expect(!fixture.plan([first, first]).canRename)
    }

    @Test func cameraDateUsesRecordedWallDayAndFallbackUsesFileCreation() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let wall = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026, month: 11, day: 12, hour: 0, minute: 5)))
        let capture = try fixture.item("capture", captureWallTime: wall)
        let fallback = try fixture.item("fallback")
        let zone = try #require(TimeZone(secondsFromGMT: -12 * 3600))
        let plan = fixture.plan(
            [capture, fallback],
            template: RenameTemplate(prefix: "Wedding_", includesCaptureDate: true),
            timeZone: zone)
        #expect(plan.canRename)
        #expect(plan.rows[0].newStem == "Wedding_20261112_001")
        let creation = try #require(
            try fixture.fileSystem.creationDate(at: fallback.set.photoSet.primary.url))
        calendar.timeZone = zone
        let components = calendar.dateComponents([.year, .month, .day], from: creation)
        let date = String(
            format: "%04d%02d%02d", components.year!, components.month!, components.day!)
        #expect(plan.rows[1].newStem == "Wedding_\(date)_002")
    }

    @Test func ambiguousSidecarAndFailedFactReadRefuse() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanup() }
        let item = try fixture.item("source")
        let candidates = [fixture.folder.file("source.xmp"), fixture.folder.file("source.ARW.xmp")]
        let ambiguous = RenameItem(
            set: ScannedPhotoSet(
                photoSet: item.set.photoSet, sidecar: .ambiguous(candidates),
                imageFiles: item.set.imageFiles))
        #expect(fixture.plan([ambiguous]).rows[0].problems.contains(.ambiguousSidecar(candidates)))
        fixture.fileSystem.fail(.contentsOfDirectory, with: POSIXError(.EACCES))
        #expect(!fixture.plan([item]).canRename)
    }
}
