import Testing

import CloveCore

@Suite struct AutoAdvancePlanTests {
    private func photos() throws -> (a: GridPhoto, b: GridPhoto, c: GridPhoto) {
        let three = try MarkingFixtures.stars(3)
        return (
            MarkingFixtures.photo("A"),
            MarkingFixtures.photo("B", marks: PhotoMarks(rating: three)),
            MarkingFixtures.photo("C")
        )
    }

    @Test func ratingsAndRejectMoveToTheNextPhotoByDefault() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        for kind in [MarkKind.rating, .reject] {
            let plan = rules.autoAdvancePlan(after: kind, from: a.id, photos: [a, b, c])
            #expect(plan.target == .nextPhoto(b.id))
            #expect(plan.markedPhoto == a.id)
            #expect(plan.advances)
        }
    }

    @Test func labelsDoNotAdvanceByDefault() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(after: .colourLabel, from: a.id, photos: [a, b, c])

        #expect(plan.target == .stay)
        #expect(plan.markedPhoto == a.id)
        #expect(!plan.advances)
    }

    @Test func labelsAdvanceWhenTheirTriggerIsOn() throws {
        let (a, b, c) = try photos()
        let settings = AppSettings(
            autoAdvance: AutoAdvance(triggers: AutoAdvanceTriggers(colourLabel: true)))
        let rules = MarkingInputRules(settings: settings)

        let plan = rules.autoAdvancePlan(after: .colourLabel, from: a.id, photos: [a, b, c])

        #expect(plan.target == .nextPhoto(b.id))
    }

    @Test func theStaySettingKeepsTheCurrentPhoto() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .stay)))

        let plan = rules.autoAdvancePlan(after: .rating, from: b.id, photos: [a, b, c])

        #expect(plan.target == .stay)
        #expect(!plan.advances)
    }

    @Test func theNextUnmarkedPhotoSkipsMarkedPhotos() throws {
        let three = try MarkingFixtures.stars(3)
        let photos = [
            MarkingFixtures.photo("A", marks: PhotoMarks()),
            MarkingFixtures.photo("B", marks: PhotoMarks()),
            MarkingFixtures.photo("C", marks: PhotoMarks(rating: three)),
            MarkingFixtures.photo("D", marks: PhotoMarks(label: ColourLabel(colour: .red))),
            MarkingFixtures.photo("E", marks: PhotoMarks(isRejected: true)),
            MarkingFixtures.photo("F", marks: PhotoMarks()),
        ]
        let rules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextUnmarkedPhoto)))

        let plan = rules.autoAdvancePlan(after: .rating, from: photos[1].id, photos: photos)

        #expect(plan.target == .nextUnmarkedPhoto(photos[5].id))
    }

    @Test func theNextUnmarkedPhotoStaysWhenNoUnmarkedPhotoFollows() throws {
        let three = try MarkingFixtures.stars(3)
        let photos = [
            MarkingFixtures.photo("A"),
            MarkingFixtures.photo("B", marks: PhotoMarks(rating: three)),
            MarkingFixtures.photo("C", marks: PhotoMarks(isRejected: true)),
        ]
        let rules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextUnmarkedPhoto)))

        let plan = rules.autoAdvancePlan(after: .rating, from: photos[0].id, photos: photos)

        #expect(plan.target == .stay)
    }

    @Test func theLastPhotoStays() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(after: .rating, from: c.id, photos: [a, b, c])

        #expect(plan.target == .stay)
        #expect(plan.markedPhoto == c.id)
    }

    @Test func aGroupViewUsesTheCallersNextUndecidedPhoto() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .nextUnmarkedPhoto)))

        let plan = rules.autoAdvancePlan(
            after: .rating, from: b.id, photos: [a, b, c], nextUndecidedInGroup: c.id)

        #expect(plan.target == .groupUndecidedPhoto(c.id))
        #expect(plan.markedPhoto == b.id)
    }

    @Test func aGroupViewDoesNotOverrideTheStaySetting() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .stay)))

        let plan = rules.autoAdvancePlan(
            after: .rating, from: b.id, photos: [a, b, c], nextUndecidedInGroup: c.id)

        #expect(plan.target == .stay)
    }

    @Test func aGroupViewWithoutAnotherUndecidedPhotoStays() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(
            after: .rating, from: b.id, photos: [a, b, c], nextUndecidedInGroup: nil)

        #expect(plan.target == .nextPhoto(c.id))
    }

    @Test func theCallersOwnUndecidedPhotoIsNotAnAdvanceTarget() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(
            after: .rating, from: b.id, photos: [a, b, c], nextUndecidedInGroup: b.id)

        #expect(plan.target == .nextPhoto(c.id))
    }

    @Test func anUnknownCurrentPhotoStays() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(
            after: .rating, from: MarkingFixtures.photoID("Z"), photos: [a, b, c])

        #expect(plan.target == .stay)
    }

    @Test func thePlanCarriesTheMarkedPhotoForUndo() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(after: .rating, from: b.id, photos: [a, b, c])

        // Undoing after auto-advance returns to the photo whose mark was undone (PRD Undo row).
        #expect(plan.markedPhoto == b.id)
        #expect(plan.target == .nextPhoto(c.id))
    }

    @Test func thePauseIsThreeTenthsOfASecond() {
        #expect(AutoAdvance.pause == .milliseconds(300))
    }
}
