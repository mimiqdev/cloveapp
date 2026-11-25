import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct PhotoInformationSheetTests {
    @Test func marksSummaryColoursOnlyStarsGoldAndKeepsUnmarkedNeutral() throws {
        let unmarked = PhotoInformationSheet.marksSummary(for: PhotoMarks(), language: .english)
        #expect(unmarked.text == "Unmarked")
        #expect(unmarked.isNeutral)
        #expect(
            unmarked.segments == [
                PhotoInformationSheet.MarkSegment(text: "Unmarked", tone: .secondary)
            ])

        let unmarkedRow = PhotoInformationSheet.marksRowSegments(
            for: PhotoMarks(), usesSidecar: true, language: .english)
        #expect(
            unmarkedRow == [
                PhotoInformationSheet.MarkSegment(text: "Unmarked", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: " · ", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: "XMP sidecar", tone: .secondary),
            ])

        let threeStars = try #require(Rating(rawValue: 3))
        let ratedAndLabelled = PhotoMarks(rating: threeStars, label: ColourLabel(colour: .green))
        let summary = PhotoInformationSheet.marksSummary(
            for: ratedAndLabelled, language: .english)
        #expect(summary.text == "★★★ · Green")
        #expect(!summary.isNeutral)
        #expect(
            summary.segments == [
                PhotoInformationSheet.MarkSegment(text: "★★★", tone: .rating),
                PhotoInformationSheet.MarkSegment(text: " · ", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: "Green", tone: .secondary),
            ])

        let ratedRow = PhotoInformationSheet.marksRowSegments(
            for: ratedAndLabelled, usesSidecar: true, language: .english)
        #expect(
            ratedRow == [
                PhotoInformationSheet.MarkSegment(text: "★★★", tone: .rating),
                PhotoInformationSheet.MarkSegment(text: " · ", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: "Green", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: " · ", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: "XMP sidecar", tone: .secondary),
            ])
        #expect(ratedRow.filter { $0.tone == .rating }.map(\.text) == ["★★★"])

        let labelOnly = PhotoMarks(label: ColourLabel(colour: .blue))
        let labelSummary = PhotoInformationSheet.marksSummary(for: labelOnly, language: .english)
        #expect(labelSummary.text == "Blue")
        #expect(labelSummary.isNeutral)

        let labelRow = PhotoInformationSheet.marksRowSegments(
            for: labelOnly, usesSidecar: false, language: .english)
        #expect(
            labelRow == [
                PhotoInformationSheet.MarkSegment(text: "Blue", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: " · ", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: "Clove only", tone: .secondary),
            ])
    }

    @Test func marksSummaryStylesRejectCleanlyWithoutGoldTint() {
        let rejected = PhotoMarks(rating: .rejected)
        let summary = PhotoInformationSheet.marksSummary(for: rejected, language: .english)
        #expect(summary.text == "Rejected")
        #expect(!summary.isNeutral)
        #expect(
            summary.segments == [
                PhotoInformationSheet.MarkSegment(text: "Rejected", tone: .reject)
            ])
        #expect(!summary.segments.contains(where: { $0.tone == .rating }))

        let rejectedWithLabel = PhotoMarks(rating: .rejected, label: ColourLabel(colour: .green))
        let combinedRow = PhotoInformationSheet.marksRowSegments(
            for: rejectedWithLabel, usesSidecar: true, language: .simplifiedChinese)
        #expect(
            combinedRow == [
                PhotoInformationSheet.MarkSegment(text: "绿色", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: " · ", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: "已淘汰", tone: .reject),
                PhotoInformationSheet.MarkSegment(text: " · ", tone: .secondary),
                PhotoInformationSheet.MarkSegment(text: "XMP 附属文件", tone: .secondary),
            ])
    }

    @Test func headerSubtitleIncludesBurstCountOnlyForVisibleMultiPhotoGroups() {
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: ["IMG_4793.JPG"], groupMemberCount: 11, language: .english)
                == "+ IMG_4793.JPG · Burst of 11")
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: [], groupMemberCount: 11, language: .english) == "Burst of 11")
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: ["IMG_4793.JPG"], groupMemberCount: nil, language: .english)
                == "+ IMG_4793.JPG")
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: ["IMG_4793.JPG"], groupMemberCount: 1, language: .english)
                == "+ IMG_4793.JPG")
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: [], groupMemberCount: nil, language: .english) == nil)
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: [], groupMemberCount: 1, language: .english) == nil)
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: ["IMG_4793.JPG"], groupMemberCount: 11, language: .simplifiedChinese)
                == "+ IMG_4793.JPG · 连拍 11 张")
        #expect(
            PhotoInformationSheet.headerSubtitle(
                companions: ["IMG_4793.JPG"], groupMemberCount: 11, language: .traditionalChinese)
                == "+ IMG_4793.JPG · 連拍 11 張")
    }

    @Test func detailGroupMemberCountRespectsVisibleGroupThresholdAndSettings() {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["a", "b", "c", "solo"])
        let a = library.identity("a")
        let b = library.identity("b")
        let c = library.identity("c")
        let solo = library.identity("solo")
        let group = BrowsingGroup(id: GroupID(rawValue: "burst-1"), members: [a, b, c])
        let photos = library.photos

        let timeline = DetailTimeline(photos: photos, groups: [group], groupsEnabled: true)
        let activeGroup = timeline.activeGroup(with: group.id)

        #expect(
            DetailMarkingView.groupMemberCount(
                for: a, timeline: timeline, expandedGroup: nil) == 3)
        #expect(
            DetailMarkingView.groupMemberCount(
                for: b, timeline: timeline, expandedGroup: activeGroup) == 3)
        #expect(
            DetailMarkingView.groupMemberCount(
                for: solo, timeline: timeline, expandedGroup: nil) == nil)

        // Filtering a group down to one visible member degrades it to standalone.
        let filteredPhotos = [photos[0], photos[3]]
        let narrowedTimeline = DetailTimeline(
            photos: filteredPhotos, groups: [group], groupsEnabled: true)
        #expect(
            DetailMarkingView.groupMemberCount(
                for: a, timeline: narrowedTimeline, expandedGroup: nil) == nil)

        // Similar groups Off suppresses group membership in Detail Info as well.
        let disabledTimeline = DetailTimeline(
            photos: photos, groups: [group], groupsEnabled: false)
        #expect(
            DetailMarkingView.groupMemberCount(
                for: a, timeline: disabledTimeline, expandedGroup: nil) == nil)
    }

    @Test func infoSheetHostsWithAndWithoutExplicitGroupCount() throws {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["a", "b", "solo"])
        let group = BrowsingGroup(
            id: GroupID(rawValue: "burst"), members: [library.identity("a"), library.identity("b")])
        library.groups = [group]
        let model = BrowsingModel(library: library)
        model.openFolder()

        let photo = try #require(model.photos.first)
        let implicitHost = UIHostingController(
            rootView: PhotoInformationSheet(browsing: model, photo: photo))
        let explicitHost = UIHostingController(
            rootView: PhotoInformationSheet(
                browsing: model, photo: photo, groupMemberCount: 2))

        implicitHost.loadViewIfNeeded()
        explicitHost.loadViewIfNeeded()
        #expect(implicitHost.view != nil)
        #expect(explicitHost.view != nil)
    }
}
