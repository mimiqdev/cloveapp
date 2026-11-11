import Foundation
import Testing

@testable import Clove

struct FolderPickHandoffTests {
    let firstURL = URL(fileURLWithPath: "/selection/first")
    let secondURL = URL(fileURLWithPath: "/selection/second")

    @Test func pickThenDismissDeliversOnce() {
        var handoff = FolderPickHandoff()
        let presentation = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: presentation) == nil)
        #expect(handoff.dismissed(presentation) == firstURL)
        #expect(handoff.dismissed(presentation) == nil)
        #expect(handoff.picked(firstURL, from: presentation) == nil)
    }

    @Test func dismissThenPickDeliversOnce() {
        var handoff = FolderPickHandoff()
        let presentation = handoff.beginPresentation()
        #expect(handoff.dismissed(presentation) == nil)
        #expect(handoff.picked(firstURL, from: presentation) == firstURL)
        #expect(handoff.picked(firstURL, from: presentation) == nil)
        #expect(handoff.dismissed(presentation) == nil)
    }

    @Test func cancellationDiscardsTheChoiceInEitherOrder() {
        var handoff = FolderPickHandoff()
        let pickedFirst = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: pickedFirst) == nil)
        handoff.cancel(pickedFirst)
        #expect(handoff.dismissed(pickedFirst) == nil)
        let dismissedFirst = handoff.beginPresentation()
        #expect(handoff.dismissed(dismissedFirst) == nil)
        handoff.cancel(dismissedFirst)
        #expect(handoff.picked(secondURL, from: dismissedFirst) == nil)
    }

    @Test func aNewPresentationDropsStoredAndLatePicksFromTheOldOne() {
        var handoff = FolderPickHandoff()
        let first = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: first) == nil)
        let second = handoff.beginPresentation()
        #expect(handoff.dismissed(first) == nil)
        #expect(handoff.picked(firstURL, from: first) == nil)
        #expect(handoff.dismissed(second) == nil)
        #expect(handoff.picked(secondURL, from: second) == secondURL)
        let third = handoff.beginPresentation()
        #expect(handoff.picked(firstURL, from: first) == nil)
        handoff.cancel(third)
        #expect(handoff.dismissed(third) == nil)
    }
}
