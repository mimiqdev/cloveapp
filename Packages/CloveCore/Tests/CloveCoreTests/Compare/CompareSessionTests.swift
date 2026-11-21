import Testing

@testable import CloveCore

@Suite("CompareSession")
struct CompareSessionTests {
    private let folder = FolderIdentity(rawValue: "compare-folder")

    private func photo(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem)
    }

    @Test("Stepping mode requires at least two unique photos containing current")
    func steppingInitializationValidation() {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")

        #expect(CompareSession(steppingFrom: p1, in: [], kind: .timeline) == nil)
        #expect(CompareSession(steppingFrom: p1, in: [p1], kind: .timeline) == nil)
        #expect(CompareSession(steppingFrom: p1, in: [p1, p1], kind: .timeline) == nil)
        #expect(
            CompareSession(steppingFrom: p1, in: [p2, photo("IMG_0003")], kind: .timeline) == nil)
        #expect(CompareSession(steppingFrom: p1, in: [p1, p2], kind: .fixedPair) == nil)
    }

    @Test(
        "Stepping from timeline picks next photo as challenger and defaults focus to B with sync on"
    )
    func steppingFromMiddleSelectsNext() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")
        let p3 = photo("IMG_0003")

        let session = try #require(
            CompareSession(steppingFrom: p1, in: [p1, p2, p3], kind: .timeline)
        )
        #expect(session.mode == .stepping)
        #expect(session.scopeKind == .timeline)
        #expect(session.reference == p1)
        #expect(session.challenger == p2)
        #expect(session.activeSide == .challenger)
        #expect(session.activePhoto == p2)
        #expect(session.isSyncLocked)
    }

    @Test("Stepping from the last photo falls back to the previous photo")
    func steppingFromLastSelectsPrevious() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")
        let p3 = photo("IMG_0003")
        let groupID = GroupID(rawValue: "g1")

        let session = try #require(
            CompareSession(steppingFrom: p3, in: [p1, p2, p3], kind: .group(groupID))
        )
        #expect(session.scopeKind == .group(groupID))
        #expect(session.reference == p3)
        #expect(session.challenger == p2)
        #expect(session.activeSide == .challenger)
    }

    @Test(
        "Fixed pair mode selects A first, B second, defaults activeSide to reference, and blocks stepping"
    )
    func fixedPairInitializationAndLocks() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")

        #expect(CompareSession(fixedPair: p1, second: p1) == nil)

        var session = try #require(CompareSession(fixedPair: p1, second: p2))
        #expect(session.mode == .fixedPair)
        #expect(session.scopeKind == .fixedPair)
        #expect(session.reference == p1)
        #expect(session.challenger == p2)
        #expect(session.activeSide == .reference)
        #expect(session.activePhoto == p1)
        #expect(session.isSyncLocked)
        #expect(!session.canStepPreviousChallenger)
        #expect(!session.canStepNextChallenger)
        #expect(!session.canPromoteChallenger)
        let steppedForward = session.stepChallenger(offset: 1)
        let steppedBackward = session.stepChallenger(offset: -1)
        let promoted = session.promoteChallengerToReference()
        let selected = session.selectChallenger(p1)
        #expect(!steppedForward)
        #expect(!steppedBackward)
        #expect(!promoted)
        #expect(!selected)
        #expect(session.reference == p1 && session.challenger == p2)
    }

    @Test("Stepping arrows and filmstrip selection skip A so A and B never match")
    func steppingAndSelectingChallengerSkipsReference() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")
        let p3 = photo("IMG_0003")
        let p4 = photo("IMG_0004")

        var session = try #require(
            CompareSession(steppingFrom: p2, in: [p1, p2, p3, p4], kind: .timeline)
        )
        // Eligible challengers when A = p2 are [p1, p3, p4]; starts at p3.
        #expect(session.eligibleChallengers == [p1, p3, p4])
        #expect(session.challenger == p3)
        #expect(session.canStepPreviousChallenger)
        #expect(session.canStepNextChallenger)

        // Stepping `<` jumps backward over A (p2) directly to p1.
        let steppedPrev = session.stepChallenger(offset: -1)
        #expect(steppedPrev)
        #expect(session.challenger == p1)
        #expect(!session.canStepPreviousChallenger)
        #expect(session.canStepNextChallenger)
        let steppedPastStart = session.stepChallenger(offset: -1)
        #expect(!steppedPastStart)

        // Stepping `>` twice moves from p1 -> p3 -> p4.
        let steppedToP3 = session.stepChallenger(offset: 1)
        #expect(steppedToP3)
        #expect(session.challenger == p3)
        let steppedToP4 = session.stepChallenger(offset: 1)
        #expect(steppedToP4)
        #expect(session.challenger == p4)
        #expect(!session.canStepNextChallenger)
        let steppedPastEnd = session.stepChallenger(offset: 1)
        #expect(!steppedPastEnd)

        // Tapping A in the filmstrip does not change B; tapping another photo replaces B.
        let selectedSameAsA = session.selectChallenger(p2)
        #expect(!selectedSameAsA)
        #expect(session.challenger == p4)
        let selectedP1 = session.selectChallenger(p1)
        #expect(selectedP1)
        #expect(session.challenger == p1)
    }

    @Test("Set as A promotes B to A and loads next distinct challenger across wrap")
    func promoteChallengerToReferenceWithThreePlusPhotos() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")
        let p3 = photo("IMG_0003")
        let p4 = photo("IMG_0004")

        var session = try #require(
            CompareSession(steppingFrom: p1, in: [p1, p2, p3, p4], kind: .timeline)
        )
        #expect(session.reference == p1 && session.challenger == p2)

        let promote1 = session.promoteChallengerToReference()
        #expect(promote1)
        #expect(session.reference == p2 && session.challenger == p3)

        let promote2 = session.promoteChallengerToReference()
        #expect(promote2)
        #expect(session.reference == p3 && session.challenger == p4)

        // Wrapping forward past p4 skips p3 (previous A) and lands on p1.
        let promote3 = session.promoteChallengerToReference()
        #expect(promote3)
        #expect(session.reference == p4 && session.challenger == p1)

        // If user had stepped B = p3 while A = p4, promoting p3 wraps past p4 (old A) to p1.
        let selectedP3 = session.selectChallenger(p3)
        #expect(selectedP3)
        #expect(session.reference == p4 && session.challenger == p3)
        let promote4 = session.promoteChallengerToReference()
        #expect(promote4)
        #expect(session.reference == p3 && session.challenger == p1)
    }

    @Test("Set as A cleanly swaps A and B when scope has exactly two photos")
    func promoteSwapsCleanlyInTwoPhotoScope() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")

        var session = try #require(
            CompareSession(steppingFrom: p1, in: [p1, p2], kind: .group(GroupID(rawValue: "pair")))
        )
        #expect(session.reference == p1 && session.challenger == p2)

        let swap1 = session.promoteChallengerToReference()
        #expect(swap1)
        #expect(session.reference == p2 && session.challenger == p1)

        let swap2 = session.promoteChallengerToReference()
        #expect(swap2)
        #expect(session.reference == p1 && session.challenger == p2)
    }

    @Test("Side switching and sync toggle update state without altering pair")
    func activeSideAndSyncToggle() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")
        var session = try #require(CompareSession(steppingFrom: p1, in: [p1, p2], kind: .timeline))

        #expect(session.activeSide == .challenger)
        #expect(session.side(of: p1) == .reference)
        #expect(session.side(of: p2) == .challenger)
        #expect(session.side(of: photo("IMG_9999")) == nil)

        session.selectSide(.reference)
        #expect(session.activeSide == .reference)
        #expect(session.activePhoto == p1)
        #expect(session.inactivePhoto == p2)

        session.toggleSyncLock()
        #expect(!session.isSyncLocked)
        session.toggleSyncLock()
        #expect(session.isSyncLocked)
    }

    @Test("Reconcile keeps valid pairs and handles deleted photos cleanly")
    func reconcileRemovedPhotos() throws {
        let p1 = photo("IMG_0001")
        let p2 = photo("IMG_0002")
        let p3 = photo("IMG_0003")

        var fixed = try #require(CompareSession(fixedPair: p1, second: p2))
        let fixedValid = fixed.reconcile(available: [p1, p2, p3])
        let fixedMissing = fixed.reconcile(available: [p1, p3])
        #expect(fixedValid)
        #expect(!fixedMissing)

        var stepping = try #require(
            CompareSession(steppingFrom: p1, in: [p1, p2, p3], kind: .timeline)
        )
        let steppedKept = stepping.reconcile(available: [p1, p3])
        #expect(steppedKept)
        #expect(stepping.reference == p1)
        #expect(stepping.challenger == p3)
        let steppedDropped = stepping.reconcile(available: [p1])
        #expect(!steppedDropped)
    }

    @Test("CompareLayoutPolicy enables Compare only on wide, landscape, and Duo expanded layouts")
    func layoutPolicyEligibility() {
        // Portrait iPhone -> excluded, no filmstrip
        let portraitPhone = CompareLayoutPolicy(
            availableWidth: 393,
            availableHeight: 852,
            isRegularWidth: false,
            isCompactHeight: false,
            isDuoExpanded: false,
            isDuoCover: false
        )
        #expect(!portraitPhone.supportsCompare)
        #expect(!portraitPhone.showsFilmstrip)

        // Duo Cover -> excluded
        let duoCover = CompareLayoutPolicy(
            availableWidth: 412,
            availableHeight: 915,
            isRegularWidth: false,
            isCompactHeight: false,
            isDuoExpanded: false,
            isDuoCover: true
        )
        #expect(!duoCover.supportsCompare)
        #expect(!duoCover.showsFilmstrip)

        // Landscape iPhone -> supported, omits filmstrip
        let landscapePhone = CompareLayoutPolicy(
            availableWidth: 852,
            availableHeight: 393,
            isRegularWidth: false,
            isCompactHeight: true,
            isDuoExpanded: false,
            isDuoCover: false
        )
        #expect(landscapePhone.supportsCompare)
        #expect(!landscapePhone.showsFilmstrip)

        // Landscape Pro Max (regular horizontal size class, compact vertical size class) -> supported, omits filmstrip
        let landscapeMaxPhone = CompareLayoutPolicy(
            availableWidth: 932,
            availableHeight: 430,
            isRegularWidth: true,
            isCompactHeight: true,
            isDuoExpanded: false,
            isDuoCover: false
        )
        #expect(landscapeMaxPhone.supportsCompare)
        #expect(!landscapeMaxPhone.showsFilmstrip)

        // Unfolded Duo -> supported, shows filmstrip
        let duoExpanded = CompareLayoutPolicy(
            availableWidth: 980,
            availableHeight: 740,
            isRegularWidth: true,
            isCompactHeight: false,
            isDuoExpanded: true,
            isDuoCover: false
        )
        #expect(duoExpanded.supportsCompare)
        #expect(duoExpanded.showsFilmstrip)

        // Unfolded Duo rotated portrait -> excluded
        let duoExpandedPortrait = CompareLayoutPolicy(
            availableWidth: 740,
            availableHeight: 980,
            isRegularWidth: false,
            isCompactHeight: false,
            isDuoExpanded: true,
            isDuoCover: false
        )
        #expect(!duoExpandedPortrait.supportsCompare)

        // iPad landscape -> supported, shows filmstrip
        let padLandscape = CompareLayoutPolicy(
            availableWidth: 1194,
            availableHeight: 834,
            isRegularWidth: true,
            isCompactHeight: false,
            isDuoExpanded: false,
            isDuoCover: false
        )
        #expect(padLandscape.supportsCompare)
        #expect(padLandscape.showsFilmstrip)

        // iPad portrait -> supported, shows filmstrip
        let padPortrait = CompareLayoutPolicy(
            availableWidth: 834,
            availableHeight: 1194,
            isRegularWidth: true,
            isCompactHeight: false,
            isDuoExpanded: false,
            isDuoCover: false
        )
        #expect(padPortrait.supportsCompare)
        #expect(padPortrait.showsFilmstrip)

        // iPad narrow Slide Over strip -> excluded
        let padSlideOver = CompareLayoutPolicy(
            availableWidth: 320,
            availableHeight: 1024,
            isRegularWidth: false,
            isCompactHeight: false,
            isDuoExpanded: false,
            isDuoCover: false
        )
        #expect(!padSlideOver.supportsCompare)
    }

    @Test("CompareSplitGeometry keeps both panes clear of a vertical fold hinge")
    func splitGeometryRespectsHinge() {
        let even = CompareSplitGeometry.layout(
            containerWidth: 1010,
            verticalFoldMinX: nil,
            verticalFoldMaxX: nil,
            defaultGap: 10
        )
        #expect(even.referenceWidth == 500)
        #expect(even.dividerWidth == 10)
        #expect(even.challengerWidth == 500)

        // Duo unfolded container after trailing side-toolbar safe area (e.g. total width 934, hinge 470...510).
        let duo = CompareSplitGeometry.layout(
            containerWidth: 934,
            verticalFoldMinX: 470,
            verticalFoldMaxX: 510,
            innerMargin: 4
        )
        #expect(duo.referenceWidth == 466)
        #expect(duo.dividerWidth == 48)
        #expect(duo.challengerWidth == 420)
        #expect(duo.referenceWidth + duo.dividerWidth + duo.challengerWidth == 934)
        // Reference ends before the hinge starts; challenger starts after the hinge ends.
        #expect(duo.referenceWidth <= 470)
        #expect(duo.referenceWidth + duo.dividerWidth >= 510)
    }
}
