import Foundation
import Testing

@testable import Clove

struct FolderPickHandoffTests {
    let firstURL = URL(fileURLWithPath: "/selection/first")
    let secondURL = URL(fileURLWithPath: "/selection/second")

    @Test func pickThenDismissDeliversOnce() {
        var handoff = FolderPickHandoff()
        var requestedAgain = false
        let presentation = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: presentation) == nil)
        #expect(handoff.dismissed(presentation, requestedAgain: &requestedAgain) == firstURL)
        #expect(handoff.dismissed(presentation, requestedAgain: &requestedAgain) == nil)
        #expect(handoff.picked(firstURL, from: presentation) == nil)
    }

    @Test func pickedFolderConsumesARequestDuringDismissal() {
        var handoff = FolderPickHandoff()
        var requestedAgain = true
        let presentation = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: presentation) == nil)
        #expect(handoff.dismissed(presentation, requestedAgain: &requestedAgain) == firstURL)
        #expect(!requestedAgain)
        #expect(handoff.presentation == presentation)
        #expect(handoff.dismissed(presentation, requestedAgain: &requestedAgain) == nil)
    }

    @Test func dismissalWithoutAPickPreservesAnotherRequest() {
        var handoff = FolderPickHandoff()
        var requestedAgain = true
        let presentation = handoff.beginPresentation()
        handoff.cancel(presentation)
        #expect(handoff.dismissed(presentation, requestedAgain: &requestedAgain) == nil)
        #expect(requestedAgain)
    }

    @Test func dismissThenPickDeliversOnce() {
        var handoff = FolderPickHandoff()
        var requestedAgain = false
        let presentation = handoff.beginPresentation()
        #expect(handoff.dismissed(presentation, requestedAgain: &requestedAgain) == nil)
        #expect(handoff.picked(firstURL, from: presentation) == firstURL)
        #expect(handoff.picked(firstURL, from: presentation) == nil)
        #expect(handoff.dismissed(presentation, requestedAgain: &requestedAgain) == nil)
    }

    @Test func cancellationDiscardsTheChoiceInEitherOrder() {
        var handoff = FolderPickHandoff()
        var requestedAgain = false
        let pickedFirst = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: pickedFirst) == nil)
        handoff.cancel(pickedFirst)
        #expect(handoff.dismissed(pickedFirst, requestedAgain: &requestedAgain) == nil)
        let dismissedFirst = handoff.beginPresentation()
        #expect(handoff.dismissed(dismissedFirst, requestedAgain: &requestedAgain) == nil)
        handoff.cancel(dismissedFirst)
        #expect(handoff.picked(secondURL, from: dismissedFirst) == nil)
    }

    @Test func aNewPresentationDropsStoredAndLatePicksFromTheOldOne() {
        var handoff = FolderPickHandoff()
        var requestedAgain = false
        let first = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: first) == nil)
        let second = handoff.beginPresentation()
        #expect(handoff.dismissed(first, requestedAgain: &requestedAgain) == nil)
        #expect(handoff.picked(firstURL, from: first) == nil)
        #expect(handoff.dismissed(second, requestedAgain: &requestedAgain) == nil)
        #expect(handoff.picked(secondURL, from: second) == secondURL)
        let third = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: first) == nil)
        handoff.cancel(third)
        #expect(handoff.dismissed(third, requestedAgain: &requestedAgain) == nil)
    }
}
