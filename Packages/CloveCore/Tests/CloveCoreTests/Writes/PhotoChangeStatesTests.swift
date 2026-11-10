import Testing

import CloveCore

/// How the save state per photo merges C4's stream and a change's awaited return
/// (PRD P0-08).
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
        states.insert(firstStatus)
        states.insert(secondStatus)

        #expect(states.latest(for: first) == firstStatus)
        #expect(states.latest(for: second) == secondStatus)
        #expect(states.count == 2)
    }

    @Test func aChangeMovesForwardThroughItsOwnStates() {
        var states = PhotoChangeStates()
        let id = MarkChangeID()
        states.insert(status(.pending, id: id))
        states.insert(status(.writing, id: id))

        #expect(states.latest(for: first)?.state == .writing)
    }

    @Test func aFinishedChangeNeverMovesBackToWriting() {
        var states = PhotoChangeStates()
        let id = MarkChangeID()
        states.insert(status(.savedInSidecar, id: id))
        states.insert(status(.writing, id: id))

        // The queue's stream can arrive after the awaited return; the finished state wins.
        #expect(states.latest(for: first)?.state == .savedInSidecar)
    }

    @Test func aNewerChangeReplacesTheOlderOne() {
        var states = PhotoChangeStates()
        states.insert(status(.pending))
        let newer = status(.pending, change: .rating(Rating(rawValue: 2) ?? .unrated))
        states.insert(newer)

        #expect(states.latest(for: first) == newer)
    }

    @Test func anOlderChangeArrivingLateDoesNotReplaceTheNewerOne() {
        var states = PhotoChangeStates()
        let olderID = MarkChangeID()
        let newerID = MarkChangeID()
        let older = status(.pending, id: olderID)
        let newer = status(.pending, id: newerID)
        states.insert(older)
        states.insert(newer)
        // PRD How marks reach disk, rule 8: a newer change supersedes the older one.
        states.insert(status(.savedInSidecar, id: olderID))
        states.insert(status(.superseded(by: newerID), id: olderID))

        #expect(states.latest(for: first) == newer)
    }

    @Test func aSupersededLatestChangeStaysReadableForRetry() {
        var states = PhotoChangeStates()
        let olderID = MarkChangeID()
        let newerID = MarkChangeID()
        states.insert(status(.pending, id: olderID))
        states.insert(status(.pending, id: newerID))
        states.insert(status(.superseded(by: newerID), id: olderID))

        // The photo's latest change is the newer one; U7's retry reads the change it holds.
        #expect(states.latest(for: first)?.id == newerID)
    }
}
