import Testing

import CloveCore

/// How the save state per photo is merged from C4's ordered state stream (PRD P0-08).
@Suite("Photo change states")
struct PhotoChangeStatesTests {
    private let first = PhotoIdentity(
        folderID: FolderIdentity(rawValue: "change-state-tests"),
        relativeFolderPath: "DCIM/100CAM", stem: "mmq05184")
    private let second = PhotoIdentity(
        folderID: FolderIdentity(rawValue: "change-state-tests"),
        relativeFolderPath: "DCIM/100CAM", stem: "mmq05185")

    /// A status for one change in a given state.
    private func status(
        _ state: MarkChangeState,
        id: MarkChangeID = MarkChangeID(),
        photo: PhotoIdentity? = nil,
        change: MarkChange = .rating(Rating(rawValue: 4) ?? .unrated)
    ) -> MarkChangeStatus {
        MarkChangeStatus(id: id, identity: photo ?? first, requested: change, state: state)
    }

    @Test func aPhotoWithNothingRequestedHasNoState() {
        #expect(PhotoChangeStates().latest(for: first) == nil)
        #expect(PhotoChangeStates().isEmpty)
    }

    @Test func eachPhotoKeepsItsOwnLatestChange() {
        var states = PhotoChangeStates()
        let firstStatus = status(.savedInSidecar)
        let secondStatus = status(.writing, photo: second)
        let acceptedFirst = states.insert(firstStatus)
        let acceptedSecond = states.insert(secondStatus)
        #expect(acceptedFirst)
        #expect(acceptedSecond)

        #expect(states.latest(for: first) == firstStatus)
        #expect(states.latest(for: second) == secondStatus)
        #expect(states.count == 2)
    }

    @Test func aChangeMovesForwardThroughItsOwnStates() {
        var states = PhotoChangeStates()
        let id = MarkChangeID()
        let admitted = states.insert(status(.pending, id: id))
        let writing = states.insert(status(.writing, id: id))
        #expect(admitted)
        #expect(writing)

        #expect(states.latest(for: first)?.state == .writing)
    }

    @Test func aFinishedChangeNeverMovesBackToWriting() {
        var states = PhotoChangeStates()
        let id = MarkChangeID()
        let saved = states.insert(status(.savedInSidecar, id: id))
        // A late buffered transition of the same change is refused, so the finished state stays.
        let lateWriting = states.insert(status(.writing, id: id))
        #expect(saved)
        #expect(!lateWriting)

        #expect(states.latest(for: first)?.state == .savedInSidecar)
    }

    @Test func aNewerChangeReplacesTheOlderOne() {
        var states = PhotoChangeStates()
        let older = states.insert(status(.pending))
        let newer = status(.pending, change: .rating(Rating(rawValue: 2) ?? .unrated))
        let acceptedNewer = states.insert(newer)
        #expect(older)
        #expect(acceptedNewer)

        #expect(states.latest(for: first) == newer)
    }

    @Test func anOlderChangesLateStateIsRefusedAfterANewerChange() {
        var states = PhotoChangeStates()
        let olderID = MarkChangeID()
        let newerID = MarkChangeID()
        let admittedOlder = states.insert(status(.pending, id: olderID))
        // The queue yields a newer change's admission before the older write finishes, so the
        // older change's final state can arrive last (PRD How marks reach disk, rule 8).
        let admittedNewer = states.insert(status(.pending, id: newerID))
        let lateSaved = states.insert(status(.savedInSidecar, id: olderID))
        let lateSuperseded = states.insert(status(.superseded(by: newerID), id: olderID))
        #expect(admittedOlder)
        #expect(admittedNewer)
        #expect(!lateSaved)
        #expect(!lateSuperseded)

        #expect(states.latest(for: first)?.id == newerID)
        #expect(states.latest(for: first)?.state == .pending)
    }

    @Test func aRefusedStatusIsShownAndALaterSuccessReplacesIt() {
        var states = PhotoChangeStates()
        // A change the queue never admitted (the folder closed) still has to reach the screen
        // (PRD P0-08: never fail silently).
        let refused = status(
            .failed(
                MarkWriteFailure(
                    reason: .locationUnavailable, message: "The folder closed.")))
        let acceptedRefusal = states.insert(refused)
        #expect(acceptedRefusal)
        #expect(states.latest(for: first)?.state.failure?.reason == .locationUnavailable)

        // A change admitted after the refusal is the newer one and replaces it.
        let success = status(.savedInSidecar)
        let acceptedSuccess = states.insert(success)
        #expect(acceptedSuccess)
        #expect(states.latest(for: first) == success)
        #expect(states.latest(for: first)?.state.failure == nil)
    }

    @Test func theFirstStateOfANewChangeIsAcceptedOnce() {
        var states = PhotoChangeStates()
        let once = status(.savedInSidecar)
        let firstCopy = states.insert(once)
        // A repeated copy of the same state is its own transition, never a newer change.
        let secondCopy = states.insert(once)
        #expect(firstCopy)
        #expect(secondCopy)
        #expect(states.latest(for: first) == once)
    }
}
