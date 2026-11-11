import CloveCore
import Testing

@Suite("Group Continue in grid order")
struct GroupContinueTests {
    private let photos = ["a", "b", "c", "d", "e"].map {
        GridPhoto(id: groupCullingPhoto($0), fileName: "\($0).ARW", time: .pending)
    }
    private var first: BrowsingGroup {
        BrowsingGroup(id: GroupID(rawValue: "first"), members: Array(photos.prefix(2).map(\.id)))
    }
    private var second: BrowsingGroup {
        BrowsingGroup(id: GroupID(rawValue: "second"), members: [photos[2].id, photos[3].id])
    }

    @Test func nextGroupIncludesCompletedGroups() {
        var rated = photos
        for index in rated.indices { rated[index].marks.rating = groupCullingRating(3) }
        #expect(
            GroupContinueDestination.next(
                after: first.id, orderedPhotos: rated, groups: [first, second],
                visiblePhotos: Set(rated.map(\.id))) == .group(second))
    }

    @Test func nextSingleOpensDetailAndTheLastItemReturnsToGrid() {
        #expect(
            GroupContinueDestination.next(
                after: first.id, orderedPhotos: photos, groups: [first],
                visiblePhotos: Set(photos.map(\.id))) == .photo(photos[2].id))
        #expect(
            GroupContinueDestination.next(
                after: second.id, orderedPhotos: Array(photos.prefix(4)), groups: [first, second],
                visiblePhotos: Set(photos.map(\.id))) == .grid)
    }

    @Test func filteringBeforeCollapsingKeepsInterleavedSinglesInGridOrder() {
        let next = BrowsingGroup(id: second.id, members: [photos[2].id, photos[4].id])
        #expect(
            GroupContinueDestination.next(
                after: first.id, orderedPhotos: photos, groups: [first, next],
                visiblePhotos: [photos[0].id, photos[3].id, photos[4].id]) == .photo(photos[3].id))
    }

    @Test func aHiddenGroupKeepsItsEntryCoverAfterTheFilterRemovedAllItsMembers() {
        let shifted = BrowsingGroup(id: first.id, members: [photos[0].id, photos[3].id])
        #expect(
            GroupContinueDestination.next(
                after: shifted.id, orderedPhotos: photos, groups: [shifted],
                visiblePhotos: [photos[1].id, photos[4].id], entryCover: photos[3].id
            ) == .photo(photos[4].id))
    }

    @Test func filteredOrderSkipsHiddenItemsEvenWhenTheCurrentGroupDisappeared() {
        #expect(
            GroupContinueDestination.next(
                after: first.id, orderedPhotos: photos, groups: [first, second],
                visiblePhotos: [photos[4].id]) == .photo(photos[4].id))
        #expect(
            GroupContinueDestination.next(
                after: first.id, orderedPhotos: photos, groups: [first, second],
                visiblePhotos: [photos[3].id, photos[4].id]) == .group(second))
        #expect(
            GroupContinueDestination.next(
                after: first.id, orderedPhotos: photos, groups: [first, second],
                visiblePhotos: []) == .grid)
    }
}
