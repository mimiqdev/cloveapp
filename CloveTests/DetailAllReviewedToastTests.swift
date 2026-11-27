import CloveCore
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
@Suite("Detail All reviewed toast", .serialized)
struct DetailAllReviewedToastTests {
    @Test func timelineTriggerSupportsStaySurvivesAutoAdvanceSkipsTimerAndBackToGridReturns()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(rejected: ["p1"], stems: ["p1", "p2", "p3"])
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }

        let p2 = library.identity("p2")
        let p3 = library.identity("p3")
        let fourStars = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(fourStars), to: p3)
        await browsing.drainActions()
        #expect(browsing.sidebarCounts.all == 3)
        #expect(browsing.sidebarCounts.unmarked == 1)

        let store = makeSettingsStore(destination: .stay)
        let presentation = AllReviewedPresentationBox(value: .focus)
        let framesBox = AllReviewedFrameBox()
        let triggerBox = AllReviewedTriggerBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: presentation,
                triggerBox: triggerBox
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        browsing.openPhoto(p2)
        try await waitFor("DetailScreen did not mount on p2") {
            self.findPreview(in: window)?.allowsMarking == true
                && framesBox.frames["clove.detail.filmstrip"] != nil
                && framesBox.frames["clove.detail.capsule"] != nil
        }
        let preview = try #require(findPreview(in: window))

        // 1. Marking the last unmarked photo with Auto-advance = .stay shows All reviewed toast.
        preview.onMarkingSwipe?(.rejected)
        try await waitFor("All reviewed toast did not appear under .stay", host: host) {
            framesBox.frames["clove.detail.allReviewedToast"] != nil
                && framesBox.frames["clove.detail.allReviewedToast.backToGrid"] != nil
        }
        #expect(browsing.state.currentPhoto == p2)
        #expect(browsing.sidebarCounts.unmarked == 0)
        #expect(framesBox.frames["clove.detail.undoToast"] == nil)

        // Toast stays visible without any auto-dismiss timer past the Undo toast delay.
        try await Task.sleep(for: DetailUndoToast.autoDismissDelay + .milliseconds(300))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(framesBox.frames["clove.detail.allReviewedToast"] != nil)

        // 2. Undoing hides the toast and leaves it hidden until the photo is marked again.
        browsing.undoLastMark(restoringNavigation: true)
        try await waitFor("Undo did not hide All reviewed toast", host: host) {
            framesBox.frames["clove.detail.allReviewedToast"] == nil
                && browsing.sidebarCounts.unmarked == 1
                && browsing.shownMarks(for: p2).isUnmarked
                && self.isPreviewBound(to: "p2.ARW", in: window)
        }

        // 3. Re-marking with Auto-advance = .nextPhoto shows toast and survives the advance onto p3.
        store.update { $0.autoAdvance = AutoAdvance(destination: .nextPhoto) }
        preview.onMarkingSwipe?(fourStars)
        try await waitFor(
            "All reviewed toast did not reappear and survive auto-advance", host: host
        ) {
            framesBox.frames["clove.detail.allReviewedToast"] != nil
                && browsing.state.currentPhoto == p3
                && self.isPreviewBound(to: "p3.ARW", in: window)
        }
        try await Task.sleep(for: .milliseconds(150))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(framesBox.frames["clove.detail.allReviewedToast"] != nil)

        // 4. Tapping Back to Grid dismisses the toast and returns to Grid.
        triggerBox.sendTrigger("clove.detail.allReviewedToast.backToGrid")
        try await waitFor("Back to Grid did not return to Grid", host: host) {
            browsing.state.route == .grid
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }
    }

    @Test func alreadyReviewedEditsAndUnmarkingDoNotTriggerUntilReMarked() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(rejected: ["p2"], stems: ["p1", "p2"])
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }

        let p1 = library.identity("p1")
        let fourStars = try #require(Rating(rawValue: 4))
        let fiveStars = try #require(Rating(rawValue: 5))
        browsing.apply(.rating(fourStars), to: p1)
        await browsing.drainActions()
        #expect(browsing.sidebarCounts.all == 2)
        #expect(browsing.sidebarCounts.unmarked == 0)

        let store = makeSettingsStore(destination: .stay)
        let presentation = AllReviewedPresentationBox(value: .focus)
        let framesBox = AllReviewedFrameBox()
        let triggerBox = AllReviewedTriggerBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: presentation,
                triggerBox: triggerBox
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        browsing.openPhoto(p1)
        try await waitFor("DetailScreen mounted on already-reviewed folder") {
            self.findPreview(in: window)?.allowsMarking == true
        }
        let preview = try #require(findPreview(in: window))

        // Editing an already-reviewed folder never triggers All reviewed toast.
        preview.onMarkingSwipe?(fiveStars)
        try await Task.sleep(for: .milliseconds(150))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(browsing.shownMarks(for: p1).rating == fiveStars)
        #expect(browsing.sidebarCounts.unmarked == 0)
        #expect(framesBox.frames["clove.detail.allReviewedToast"] == nil)

        // Clearing back to unmarked leaves 1 unmarked photo and does not trigger the toast.
        preview.onMarkingSwipe?(.unrated)
        try await Task.sleep(for: .milliseconds(150))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(browsing.shownMarks(for: p1).isUnmarked)
        #expect(browsing.sidebarCounts.unmarked == 1)
        #expect(framesBox.frames["clove.detail.allReviewedToast"] == nil)

        // Marking that newly unmarked photo now transitions 1 -> 0 and shows the toast.
        preview.onMarkingSwipe?(fiveStars)
        try await waitFor("All reviewed toast appeared after marking cleared photo") {
            framesBox.frames["clove.detail.allReviewedToast"] != nil
        }
    }

    @Test func wholeFolderCountIgnoresActiveFilterAndReplacesHiddenByFilterUndoToast() async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(rejected: [], stems: ["p1", "p2", "p3"])
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }

        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        let p3 = library.identity("p3")
        let fourStars = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(fourStars), to: p3)
        await browsing.drainActions()

        // Active Unmarked filter hides each marked photo; first mark leaves 1 unmarked in folder
        // so Undo toast shows; second mark finishes folder and replaces Undo toast with All reviewed.
        browsing.setFilter(.unmarked)
        browsing.openPhoto(p1)

        let store = makeSettingsStore(destination: .nextPhoto)
        let presentation = AllReviewedPresentationBox(value: .focus)
        let framesBox = AllReviewedFrameBox()
        let triggerBox = AllReviewedTriggerBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: presentation,
                triggerBox: triggerBox
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("DetailScreen mounted under Unmarked filter", host: host) {
            self.findPreview(in: window)?.allowsMarking == true
                && browsing.state.currentPhoto == p1
                && self.isPreviewBound(to: "p1.ARW", in: window)
        }
        let preview = try #require(findPreview(in: window))

        preview.onMarkingSwipe?(.rejected)
        try await waitFor(
            "hidden-by-filter Undo toast appeared while 1 unmarked remained", host: host
        ) {
            framesBox.frames["clove.detail.undoToast"] != nil
                && browsing.state.currentPhoto == p2
                && self.isPreviewBound(to: "p2.ARW", in: window)
        }
        #expect(framesBox.frames["clove.detail.allReviewedToast"] == nil)
        #expect(browsing.sidebarCounts.unmarked == 1)

        preview.onMarkingSwipe?(.rejected)
        try await waitFor(
            "All reviewed toast replaced Undo toast on last unmarked photo", host: host
        ) {
            framesBox.frames["clove.detail.allReviewedToast"] != nil
                && framesBox.frames["clove.detail.undoToast"] == nil
        }
        #expect(browsing.sidebarCounts.unmarked == 0)
        #expect(browsing.canUndoMark)

        // Marking under a non-Unmarked filter (e.g. Rated 4+) still waits for the whole folder.
        browsing.undoLastMark(restoringNavigation: true)
        try await waitFor("Undo restored p2", host: host) {
            browsing.sidebarCounts.unmarked == 1
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }
        browsing.setFilter(.ratedAtLeast(fourStars))
        browsing.openPhoto(p3)
        try await waitFor("DetailScreen opened p3 under Rated filter", host: host) {
            browsing.state.currentPhoto == p3
                && preview.allowsMarking
                && self.isPreviewBound(to: "p3.ARW", in: window)
        }
        preview.onMarkingSwipe?(.rejected)
        try await Task.sleep(for: .milliseconds(150))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(browsing.sidebarCounts.unmarked == 1)
        #expect(framesBox.frames["clove.detail.allReviewedToast"] == nil)
    }

    @Test func groupFocusSingleMarkAndRejectUnmarkedFinishGroupAndPadLayoutClearance()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(
            rejected: [], stems: ["standalone", "g1a", "g1b", "g1c"])
        let group = BrowsingGroup(
            id: GroupID(rawValue: "g1"),
            members: ["g1a", "g1b", "g1c"].map { library.identity($0) })
        library.groups = [group]

        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder with group did not open") {
            !browsing.isFolderOpening && !browsing.groups.isEmpty
        }

        let standalone = library.identity("standalone")
        let g1a = library.identity("g1a")
        let g1b = library.identity("g1b")
        let g1c = library.identity("g1c")
        let fourStars = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(fourStars), to: g1a)
        await browsing.drainActions()

        let store = makeSettingsStore(destination: .nextPhoto)
        let presentation = AllReviewedPresentationBox(value: .focus)
        let framesBox = AllReviewedFrameBox()
        let triggerBox = AllReviewedTriggerBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 680, height: 768)
        let host = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: presentation,
                triggerBox: triggerBox,
                idiom: .pad
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // 1. Batch Reject N unmarked while another photo outside the group is still unmarked shows Undo toast.
        browsing.openGroup(group.id, on: g1a)
        try await waitFor("Group Focus Reject unmarked pill appeared") {
            framesBox.frames["clove.detail.rejectUnmarked"] != nil
                && self.findPreview(in: window)?.allowsMarking == true
        }
        triggerBox.sendTrigger("clove.detail.rejectUnmarked")
        try await waitFor("Reject batch Undo toast appeared while standalone remained unmarked") {
            framesBox.frames["clove.detail.undoToast"] != nil
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }

        browsing.undoLastMark(restoringNavigation: true)
        try await waitFor("Undo restored group unmarked members") {
            framesBox.frames["clove.detail.undoToast"] == nil
                && browsing.sidebarCounts.unmarked == 3
        }

        // 2. Mark standalone, then Reject 2 unmarked finishes the folder -> All reviewed toast replaces Undo toast
        // and survives auto-advance collapse, clearing inspection pill / filmstrip / capsule cleanly.
        browsing.apply(.rating(fourStars), to: standalone)
        await browsing.drainActions()
        browsing.openGroup(group.id, on: g1a)
        try await waitFor("Reject 2 unmarked pill ready for final folder cull") {
            framesBox.frames["clove.detail.rejectUnmarked"] != nil
                && browsing.expandedGroup == group.id
                && browsing.sidebarCounts.unmarked == 2
        }
        triggerBox.sendTrigger("clove.detail.rejectUnmarked")
        try await waitFor(
            "All reviewed toast replaced Reject batch Undo toast and survived collapse"
        ) {
            framesBox.frames["clove.detail.allReviewedToast"] != nil
                && framesBox.frames["clove.detail.undoToast"] == nil
                && framesBox.frames["clove.detail.rejectUnmarked"] == nil
                && browsing.expandedGroup == nil
        }
        #expect(browsing.canUndoMark)
        let toastFrame = try #require(framesBox.frames["clove.detail.allReviewedToast"])
        let inspectionFrame = try #require(framesBox.frames["clove.detail.inspectionPill"])
        let stripFrame = try #require(framesBox.frames["clove.detail.filmstrip"])
        let capsuleFrame = try #require(framesBox.frames["clove.detail.capsule"])
        #expect(!toastFrame.intersects(inspectionFrame))
        #expect(toastFrame.minX >= inspectionFrame.maxX + 11.5)
        #expect(!toastFrame.intersects(stripFrame))
        #expect(!toastFrame.intersects(capsuleFrame))
        #expect(abs(toastFrame.midY - inspectionFrame.midY) <= 1.5)

        // 3. Undo batch finish hides All reviewed toast, restores g1b & g1c unmarked, and single-photo marks finish folder.
        browsing.undoLastMark(restoringNavigation: true)
        try await waitFor("Undo restored Group Focus unmarked photos", host: host) {
            framesBox.frames["clove.detail.allReviewedToast"] == nil
                && browsing.expandedGroup == group.id
                && browsing.sidebarCounts.unmarked == 2
        }
        browsing.selectGroupPhoto(g1b)
        try await waitFor("Selected g1b", host: host) {
            browsing.state.currentPhoto == g1b
                && self.findPreview(in: window)?.allowsMarking == true
                && self.isPreviewBound(to: "g1b.ARW", in: window)
        }
        let preview = try #require(findPreview(in: window))
        preview.onMarkingSwipe?(fourStars)
        try await waitFor("Marked g1b and advanced to g1c", host: host) {
            browsing.state.currentPhoto == g1c
                && browsing.sidebarCounts.unmarked == 1
                && self.isPreviewBound(to: "g1c.ARW", in: window)
        }
        #expect(framesBox.frames["clove.detail.allReviewedToast"] == nil)

        preview.onMarkingSwipe?(.rejected)
        try await waitFor(
            "Single-photo Group Focus mark showed All reviewed toast and survived exit", host: host
        ) {
            framesBox.frames["clove.detail.allReviewedToast"] != nil
                && browsing.sidebarCounts.unmarked == 0
                && browsing.expandedGroup == nil
        }
    }

    @Test
    func
        markingLastUnmarkedPhotoViaCollapsedGroupRepresentativeEntersGroupFocusAndShowsAllReviewedToast()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(rejected: ["g2"], stems: ["p1", "g1", "g2"])
        let group = BrowsingGroup(
            id: GroupID(rawValue: "g1"),
            members: [library.identity("g1"), library.identity("g2")])
        library.groups = [group]

        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder with group did not open") {
            !browsing.isFolderOpening && !browsing.groups.isEmpty
        }

        let p1 = library.identity("p1")
        let g1 = library.identity("g1")
        let fourStars = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(fourStars), to: p1)
        await browsing.drainActions()
        #expect(browsing.sidebarCounts.unmarked == 1)

        let store = makeSettingsStore(destination: .stay)
        let presentation = AllReviewedPresentationBox(value: .focus)
        let framesBox = AllReviewedFrameBox()
        let triggerBox = AllReviewedTriggerBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: presentation,
                triggerBox: triggerBox
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        browsing.openPhoto(g1)
        try await waitFor("collapsed group representative mounted", host: host) {
            self.findPreview(in: window)?.allowsMarking == true
                && framesBox.frames["clove.detail.expandGroup"] != nil
                && browsing.expandedGroup == nil
        }

        // Marking under .stay enters Group Focus on g1, shows All reviewed toast, and is NOT
        // dismissed by the nil -> group.id expansion change.
        let preview = try #require(findPreview(in: window))
        preview.onMarkingSwipe?(fourStars)
        try await waitFor("All reviewed toast appeared in newly expanded Group Focus", host: host) {
            browsing.expandedGroup == group.id
                && browsing.shownMarks(for: g1).rating == fourStars
                && framesBox.frames["clove.detail.allReviewedToast"] != nil
                && framesBox.frames["clove.detail.filmstrip.expandedGroup"] != nil
        }
        try await Task.sleep(for: .milliseconds(150))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(framesBox.frames["clove.detail.allReviewedToast"] != nil)

        // Undo hides All reviewed toast, restores g1 unmarked, and stays in Group Focus.
        browsing.undoLastMark(restoringNavigation: true)
        try await waitFor("Undo hid All reviewed toast while staying in Group Focus", host: host) {
            framesBox.frames["clove.detail.allReviewedToast"] == nil
                && browsing.expandedGroup == group.id
                && browsing.shownMarks(for: g1).isUnmarked
                && browsing.sidebarCounts.unmarked == 1
        }

        // Collapse back to Timeline and re-mark with auto-advance = .nextPhoto: expands into
        // Group Focus, shows All reviewed toast, and keeps it across Group Focus auto-advance exit.
        browsing.collapseGroup()
        try await waitFor("collapsed back to Timeline", host: host) {
            browsing.expandedGroup == nil
                && framesBox.frames["clove.detail.expandGroup"] != nil
        }
        store.update { $0.autoAdvance = AutoAdvance(destination: .nextPhoto) }
        preview.onMarkingSwipe?(fourStars)
        try await waitFor(
            "All reviewed toast survived expand-then-mark and Group Focus exit", host: host
        ) {
            framesBox.frames["clove.detail.allReviewedToast"] != nil
                && browsing.sidebarCounts.unmarked == 0
                && browsing.expandedGroup == nil
                && browsing.state.currentPhoto == p1
        }
    }

    @Test func dismissalCoversNavigationPhotoTapMarkingCompareAndFailureToastPrecedence()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(rejected: [], stems: ["p1", "p2", "p3"])
        let group = BrowsingGroup(
            id: GroupID(rawValue: "g1"),
            members: [library.identity("p2"), library.identity("p3")])
        library.groups = [group]

        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder did not open") {
            !browsing.isFolderOpening && !browsing.groups.isEmpty
        }

        let p1 = library.identity("p1")
        let p2 = library.identity("p2")
        let p3 = library.identity("p3")
        let fourStars = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(fourStars), to: p2)
        browsing.apply(.rating(fourStars), to: p3)
        await browsing.drainActions()

        let store = makeSettingsStore(destination: .stay)
        let presentation = AllReviewedPresentationBox(value: .focus)
        let framesBox = AllReviewedFrameBox()
        let triggerBox = AllReviewedTriggerBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: presentation,
                triggerBox: triggerBox
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                framesBox.frames = $0
            })
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func triggerToastOnP1() async throws {
            browsing.apply(.rating(.unrated), to: p1)
            await browsing.drainActions()
            browsing.openPhoto(p1)
            try await waitFor("p1 ready to mark", host: host) {
                browsing.state.currentPhoto == p1
                    && self.findPreview(in: window)?.allowsMarking == true
                    && self.isPreviewBound(to: "p1.ARW", in: window)
                    && framesBox.frames["clove.detail.allReviewedToast"] == nil
            }
            let preview = try #require(findPreview(in: window))
            preview.onMarkingSwipe?(fourStars)
            try await waitFor("All reviewed toast appeared", host: host) {
                framesBox.frames["clove.detail.allReviewedToast"] != nil
            }
        }

        // 1. Tapping photo canvas dismisses the toast.
        try await triggerToastOnP1()
        let preview = try #require(findPreview(in: window))
        preview.onChromeToggle?()
        try await waitFor("photo tap dismissed All reviewed toast", host: host) {
            framesBox.frames["clove.detail.allReviewedToast"] == nil
        }
        preview.onChromeToggle?()
        try await waitFor("chrome restored", host: host) {
            framesBox.frames["clove.detail.capsule"] != nil
        }

        // 2. Starting a mark via toolbar rating picker dismisses the toast.
        try await triggerToastOnP1()
        triggerBox.sendTrigger("clove.detail.capsule.rating")
        try await waitFor("starting mark dismissed All reviewed toast", host: host) {
            framesBox.frames["clove.detail.allReviewedToast"] == nil
        }
        // Dismiss opened tap picker before next check.
        preview.onSwipeBegin?()

        // 3. Stepping to next photo dismisses the toast.
        try await triggerToastOnP1()
        preview.onStep?(1)
        try await waitFor("stepping dismissed All reviewed toast", host: host) {
            browsing.state.currentPhoto != p1
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }

        // 4. Expanding and collapsing a group dismisses the toast.
        try await triggerToastOnP1()
        browsing.openGroup(group.id, on: p2)
        try await waitFor("expanding group dismissed All reviewed toast", host: host) {
            browsing.expandedGroup == group.id
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }

        // 5. Changing filter dismisses the toast.
        try await triggerToastOnP1()
        browsing.setFilter(.ratedAtLeast(fourStars))
        try await waitFor("changing filter dismissed All reviewed toast", host: host) {
            browsing.state.filter == .ratedAtLeast(fourStars)
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }
        browsing.setFilter(.all)

        // 6. Entering Compare (in landscape where Compare is supported) dismisses the toast, and
        // exiting Compare does not bring it back.
        window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
        host.traitOverrides.verticalSizeClass = .compact
        try await triggerToastOnP1()
        let timeline = DetailTimeline(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: true)
        #expect(browsing.enterCompareFromDetail(timeline: timeline))
        try await waitFor("entering Compare dismissed All reviewed toast", host: host) {
            browsing.compareSession != nil
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }
        browsing.exitCompare()
        try await waitFor("exited Compare without restoring All reviewed toast", host: host) {
            browsing.compareSession == nil
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        host.traitOverrides.verticalSizeClass = .regular

        // 7. Save failure arriving after last mark supersedes All reviewed toast,
        // and an already-visible failure toast keeps priority over All reviewed toast.
        browsing.apply(.rating(.unrated), to: p1)
        await browsing.drainActions()
        browsing.openPhoto(p1)
        try await waitFor("p1 ready for failure test", host: host) {
            browsing.state.currentPhoto == p1
                && self.findPreview(in: window)?.allowsMarking == true
                && self.isPreviewBound(to: "p1.ARW", in: window)
        }
        let failurePreview = try #require(findPreview(in: window))
        library.failNext.insert(p1)
        failurePreview.onMarkingSwipe?(fourStars)
        try await waitFor("save failure toast superseded All reviewed toast", host: host) {
            browsing.failureToastMessage != nil
                && self.hasVisibleToastGlass(in: window)
                && framesBox.frames["clove.detail.allReviewedToast"] == nil
        }

        // While failure toast is already showing, marking the last unmarked photo must not overwrite it.
        failurePreview.onMarkingSwipe?(fourStars)
        try await Task.sleep(for: .milliseconds(150))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(browsing.failureToastMessage != nil)
        #expect(hasVisibleToastGlass(in: window))
        #expect(framesBox.frames["clove.detail.allReviewedToast"] == nil)
    }

    @Test func switchingPresentationOutOfFocusViewDismissesToastForExplicitAndDuoBindings()
        async throws
    {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let library = ControlledPhotoLibrary(rejected: ["p2"], stems: ["p1", "p2"])
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()
        library.reportScanFinished()
        try await waitFor("folder did not open") { !browsing.isFolderOpening }

        let p1 = library.identity("p1")
        let fourStars = try #require(Rating(rawValue: 4))
        let store = makeSettingsStore(destination: .stay)

        // 1. Explicit `presentation` binding switching `.focus` -> `.photoPreview` dismisses toast.
        let explicitPresentation = AllReviewedPresentationBox(value: .focus)
        let explicitFrames = AllReviewedFrameBox()
        let explicitTriggers = AllReviewedTriggerBox()
        let explicitWindow = UIWindow(windowScene: scene)
        explicitWindow.frame = CGRect(x: 0, y: 0, width: 900, height: 768)
        let explicitHost = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: explicitPresentation,
                triggerBox: explicitTriggers,
                idiom: .pad
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                explicitFrames.frames = $0
            })
        explicitHost.traitOverrides.horizontalSizeClass = .regular
        explicitWindow.rootViewController = explicitHost
        explicitWindow.makeKeyAndVisible()
        defer {
            explicitWindow.isHidden = true
            explicitWindow.rootViewController = nil
        }

        browsing.openPhoto(p1)
        try await waitFor("iPad DetailScreen mounted in Focus View", host: explicitHost) {
            self.findPreview(in: explicitWindow)?.allowsMarking == true
                && self.isPreviewBound(to: "p1.ARW", in: explicitWindow)
        }
        let explicitPreview = try #require(findPreview(in: explicitWindow))
        explicitPreview.onMarkingSwipe?(fourStars)
        try await waitFor("All reviewed toast appeared in Focus View", host: explicitHost) {
            explicitFrames.frames["clove.detail.allReviewedToast"] != nil
        }

        explicitPresentation.value = .photoPreview
        try await waitFor(
            "Switching presentation to Photo Preview dismissed All reviewed toast",
            host: explicitHost
        ) {
            explicitFrames.frames["clove.detail.allReviewedToast"] == nil
                && explicitFrames.frames["clove.detail.filmstrip"] == nil
        }
        explicitPresentation.value = .focus
        try await waitFor(
            "Returned to Focus View without resurrecting All reviewed toast", host: explicitHost
        ) {
            explicitFrames.frames["clove.detail.filmstrip"] != nil
        }
        #expect(explicitFrames.frames["clove.detail.allReviewedToast"] == nil)

        // 2. Duo `duo?.presentation` binding switching `.focus` -> `.photoPreview` dismisses toast.
        explicitWindow.isHidden = true
        explicitWindow.rootViewController = nil
        browsing.apply(.rating(.unrated), to: p1)
        await browsing.drainActions()

        let duoPresentation = AllReviewedPresentationBox(value: .focus)
        let duoFrames = AllReviewedFrameBox()
        let duoTriggers = AllReviewedTriggerBox()
        let duoWindow = UIWindow(windowScene: scene)
        duoWindow.frame = CGRect(x: 0, y: 0, width: 900, height: 768)
        let duoHost = UIHostingController(
            rootView: AllReviewedDetailHost(
                browsing: browsing,
                images: SampleDetailImages(),
                store: store,
                presentation: duoPresentation,
                usesDuoLayout: true,
                triggerBox: duoTriggers,
                idiom: .pad
            )
            .environment(\.cloveTheme, .dark)
            .onPreferenceChange(TapPickerFramesPreferenceKey.self) {
                duoFrames.frames = $0
            })
        duoHost.traitOverrides.horizontalSizeClass = .regular
        duoWindow.rootViewController = duoHost
        duoWindow.makeKeyAndVisible()
        defer {
            duoWindow.isHidden = true
            duoWindow.rootViewController = nil
        }

        try await waitFor("Duo DetailScreen mounted in Focus View", host: duoHost) {
            self.findPreview(in: duoWindow)?.allowsMarking == true
                && self.isPreviewBound(to: "p1.ARW", in: duoWindow)
        }
        let duoPreview = try #require(findPreview(in: duoWindow))
        duoPreview.onMarkingSwipe?(fourStars)
        try await waitFor("All reviewed toast appeared in Duo Focus View", host: duoHost) {
            duoFrames.frames["clove.detail.allReviewedToast"] != nil
        }

        duoPresentation.value = .photoPreview
        try await waitFor(
            "Switching Duo presentation to Photo Preview dismissed All reviewed toast",
            host: duoHost
        ) {
            duoFrames.frames["clove.detail.allReviewedToast"] == nil
                && duoFrames.frames["clove.detail.filmstrip"] == nil
        }
        duoPresentation.value = .focus
        try await waitFor(
            "Returned Duo to Focus View without resurrecting All reviewed toast", host: duoHost
        ) {
            duoFrames.frames["clove.detail.filmstrip"] != nil
        }
        #expect(duoFrames.frames["clove.detail.allReviewedToast"] == nil)
    }

    private func makeSettingsStore(destination: AutoAdvanceDestination) -> SettingsStore {
        let storage = SampleSettingsStorage()
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage)
        store.markGestureGuideSeen()
        store.update {
            $0.autoAdvance = AutoAdvance(destination: destination)
        }
        return store
    }

    private func waitFor(
        _ message: String,
        timeout: Duration = .seconds(6),
        host: UIViewController? = nil,
        condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            host?.view.setNeedsLayout()
            host?.view.layoutIfNeeded()
            if condition() { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        host?.view.setNeedsLayout()
        host?.view.layoutIfNeeded()
        try #require(condition(), Comment(rawValue: message))
    }

    private func isPreviewBound(to fileName: String, in view: UIView) -> Bool {
        guard
            let previewElement = findAccessibilityElement(
                withIdentifier: "clove.detail.preview", in: view),
            let label = previewElement.accessibilityLabel
        else { return false }
        return label.contains(fileName)
    }

    private func findPreview(in view: UIView) -> DetailZoomContainerView? {
        if let preview = view as? DetailZoomContainerView { return preview }
        for child in view.subviews {
            if let preview = findPreview(in: child) { return preview }
        }
        return nil
    }

    private func findAccessibilityElement(
        withIdentifier identifier: String, in view: UIView
    ) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for child in view.subviews {
            if let found = findAccessibilityElement(withIdentifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    private func hasVisibleToastGlass(in window: UIWindow) -> Bool {
        func walk(_ view: UIView) -> Bool {
            let frame = view.convert(view.bounds, to: window)
            if String(describing: type(of: view)).contains("GlassInteractionView"),
                !view.isHidden, view.alpha > 0.01, view.layer.opacity > 0.01,
                frame.width > 120, frame.height >= 52
            {
                return true
            }
            return view.subviews.contains(where: walk)
        }
        return walk(window)
    }
}

@MainActor
@Observable
private final class AllReviewedPresentationBox {
    var value: DetailPresentation

    init(value: DetailPresentation) {
        self.value = value
    }
}

@MainActor
private final class AllReviewedFrameBox {
    var frames: [String: CGRect] = [:]
}

@MainActor
@Observable
private final class AllReviewedTriggerBox {
    var trigger: TapPickerTriggerRequest?
    private var nonce = 0

    func sendTrigger(_ id: String) {
        nonce += 1
        trigger = TapPickerTriggerRequest(id: id, nonce: nonce)
    }
}

private struct AllReviewedDetailHost: View {
    let browsing: BrowsingModel
    let images: any DetailImageSource
    let store: SettingsStore
    @Bindable var presentation: AllReviewedPresentationBox
    var usesDuoLayout = false
    let triggerBox: AllReviewedTriggerBox
    var idiom: UIUserInterfaceIdiom = .phone

    var body: some View {
        DetailScreen(
            browsing: browsing,
            images: images,
            duo: usesDuoLayout
                ? DuoDetailLayout(presentation: $presentation.value, showsGrid: true) : nil,
            presentation: usesDuoLayout ? nil : $presentation.value
        )
        .environment(store)
        .environment(\.cloveUserInterfaceIdiom, idiom)
        .environment(\.scenePhase, .active)
        .environment(\.tapPickerTriggerRequest, triggerBox.trigger)
    }
}
