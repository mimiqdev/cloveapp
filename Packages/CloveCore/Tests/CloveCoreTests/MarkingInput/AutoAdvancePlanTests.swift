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
            MarkingFixtures.photo("E", marks: PhotoMarks(rating: .rejected)),
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
            MarkingFixtures.photo("C", marks: PhotoMarks(rating: .rejected)),
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
            after: .rating, from: b.id, photos: [a, b, c], group: .nextUndecidedPhoto(c.id))

        #expect(plan.target == .groupUndecidedPhoto(c.id))
        #expect(plan.markedPhoto == b.id)
    }

    @Test func aGroupViewDoesNotOverrideTheStaySetting() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules(
            settings: AppSettings(autoAdvance: AutoAdvance(destination: .stay)))

        let plan = rules.autoAdvancePlan(
            after: .rating, from: b.id, photos: [a, b, c], group: .nextUndecidedPhoto(c.id))

        #expect(plan.target == .stay)
    }

    @Test func aCompletedGroupStaysForTheGroupViewToFinish() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        // Later photos still exist, but the group is over: moving through them is the group
        // view's completion job, not the ordinary next-photo policy (PRD P0-12).
        let plan = rules.autoAdvancePlan(
            after: .rating, from: b.id, photos: [a, b, c], group: .complete)

        #expect(plan.target == .stay)
        #expect(plan.markedPhoto == b.id)
    }

    @Test func aGroupAnswerNamingTheCurrentPhotoIsNotAMove() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(
            after: .rating, from: b.id, photos: [a, b, c], group: .nextUndecidedPhoto(b.id))

        #expect(plan.target == .stay)
    }

    @Test func aRegularDetailViewUsesThePolicyDestination() throws {
        let (a, b, c) = try photos()
        let rules = MarkingInputRules()

        let plan = rules.autoAdvancePlan(after: .rating, from: b.id, photos: [a, b, c])

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

    @Test func markChangeIsClearingIdentifiesClearedMarksByKind() throws {
        let three = try MarkingFixtures.stars(3)
        let red = ColourLabel(colour: .red)

        #expect(MarkChange(rating: .unrated).isClearing(for: .rating))
        #expect(MarkChange(rating: .unrated).isClearing(for: .reject))
        #expect(!MarkChange(rating: .unrated).isClearing(for: .colourLabel))

        #expect(MarkChange(label: .clear).isClearing(for: .colourLabel))
        #expect(!MarkChange(label: .clear).isClearing(for: .rating))
        #expect(!MarkChange(label: .clear).isClearing(for: .reject))

        #expect(!MarkChange(rating: three).isClearing(for: .rating))
        #expect(!MarkChange(rating: .rejected).isClearing(for: .reject))
        #expect(!MarkChange(label: red).isClearing(for: .colourLabel))
        #expect(!MarkChange().isClearing(for: .rating))
        #expect(!MarkChange().isClearing(for: .reject))
        #expect(!MarkChange().isClearing(for: .colourLabel))
    }

    @Test func clearingRatingViaBarKeyOrSwipeStaysWithoutAdvancing() throws {
        let (a, b, c) = try photos()
        let three = try MarkingFixtures.stars(3)
        let ratedAndLabelled = PhotoMarks(rating: three, label: ColourLabel(colour: .red))

        let destinations: [AutoAdvanceDestination] = [.nextPhoto, .nextUnmarkedPhoto]
        for destination in destinations {
            let rules = MarkingInputRules(
                settings: AppSettings(autoAdvance: AutoAdvance(destination: destination)))
            let inputs: [MarkingResult] = [
                rules.result(forRating: three, marks: ratedAndLabelled),
                rules.result(for: .rating(.unrated), marks: ratedAndLabelled),
                rules.result(forSwipeRating: .unrated, marks: ratedAndLabelled, isZoomed: false),
            ]
            for input in inputs {
                guard case .mark(let change, let kind) = input else {
                    Issue.record("Expected clearing input to produce .mark")
                    continue
                }
                let plan = rules.autoAdvancePlan(
                    after: kind, change: change, from: a.id, photos: [a, b, c])
                #expect(plan.target == .stay)
                #expect(!plan.advances)

                let groupPlan = rules.autoAdvancePlan(
                    after: kind, change: change, from: a.id, photos: [a, b, c],
                    group: .nextUndecidedPhoto(c.id))
                #expect(groupPlan.target == .stay)
                #expect(!groupPlan.advances)
            }
        }
    }

    @Test func togglingRejectOffStaysWithoutAdvancing() throws {
        let (a, b, c) = try photos()
        let rejected = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .green))

        for destination in [AutoAdvanceDestination.nextPhoto, .nextUnmarkedPhoto] {
            let rules = MarkingInputRules(
                settings: AppSettings(autoAdvance: AutoAdvance(destination: destination)))
            let inputs: [MarkingResult] = [
                rules.result(forRejectToggle: rejected),
                rules.result(forSwipeRating: .unrated, marks: rejected, isZoomed: false),
            ]
            for input in inputs {
                guard case .mark(let change, let kind) = input else {
                    Issue.record("Expected un-reject input to produce .mark")
                    continue
                }
                let plan = rules.autoAdvancePlan(
                    after: kind, change: change, from: a.id, photos: [a, b, c])
                #expect(plan.target == .stay)
                #expect(!plan.advances)

                let groupPlan = rules.autoAdvancePlan(
                    after: kind, change: change, from: a.id, photos: [a, b, c],
                    group: .nextUndecidedPhoto(c.id))
                #expect(groupPlan.target == .stay)
                #expect(!groupPlan.advances)
            }
        }
    }

    @Test func clearingColourLabelStaysWithoutAdvancingEvenWhenTriggerIsOn() throws {
        let (a, b, c) = try photos()
        let three = try MarkingFixtures.stars(3)
        let red = ColourLabel(colour: .red)
        let ratedAndLabelled = PhotoMarks(rating: three, label: red)

        for destination in [AutoAdvanceDestination.nextPhoto, .nextUnmarkedPhoto] {
            let rules = MarkingInputRules(
                settings: AppSettings(
                    autoAdvance: AutoAdvance(
                        destination: destination,
                        triggers: AutoAdvanceTriggers(colourLabel: true))))
            let inputs: [MarkingResult] = [
                rules.result(forLabel: red, marks: ratedAndLabelled),
                rules.result(forLabel: .clear, marks: ratedAndLabelled),
                rules.result(for: .colourLabel(.red), marks: ratedAndLabelled),
            ]
            for input in inputs {
                guard case .mark(let change, let kind) = input else {
                    Issue.record("Expected clearing label input to produce .mark")
                    continue
                }
                let plan = rules.autoAdvancePlan(
                    after: kind, change: change, from: a.id, photos: [a, b, c])
                #expect(plan.target == .stay)
                #expect(!plan.advances)

                let groupPlan = rules.autoAdvancePlan(
                    after: kind, change: change, from: a.id, photos: [a, b, c],
                    group: .nextUndecidedPhoto(c.id))
                #expect(groupPlan.target == .stay)
                #expect(!groupPlan.advances)
            }
        }
    }

    @Test func positiveMarksContinueToAdvance() throws {
        let (a, b, c) = try photos()
        let three = try MarkingFixtures.stars(3)
        let blue = ColourLabel(colour: .blue)
        let rules = MarkingInputRules(
            settings: AppSettings(
                autoAdvance: AutoAdvance(
                    destination: .nextPhoto,
                    triggers: AutoAdvanceTriggers(colourLabel: true))))

        let ratingPlan = rules.autoAdvancePlan(
            after: .rating, change: MarkChange(rating: three), from: a.id, photos: [a, b, c])
        #expect(ratingPlan.target == .nextPhoto(b.id))

        let rejectPlan = rules.autoAdvancePlan(
            after: .reject, change: MarkChange(rating: .rejected), from: a.id, photos: [a, b, c])
        #expect(rejectPlan.target == .nextPhoto(b.id))

        let labelPlan = rules.autoAdvancePlan(
            after: .colourLabel, change: MarkChange(label: blue), from: a.id, photos: [a, b, c])
        #expect(labelPlan.target == .nextPhoto(b.id))
    }
}
