import Testing

@testable import CloveCore

struct DetailPresentationTests {
    @Test func dividerSettlesOnlyAtDesignedPresentations() {
        #expect(DetailPresentation.grid.gridFraction == 1)
        #expect(DetailPresentation.photoPreview.gridFraction == 0.3)
        #expect(DetailPresentation.focus.gridFraction == 0)

        #expect(DetailPresentation.photoPreview.showsPhotoGrid)
        #expect(!DetailPresentation.photoPreview.showsFilmstrip)
        #expect(!DetailPresentation.focus.showsPhotoGrid)
        #expect(DetailPresentation.focus.showsFilmstrip)

        #expect(DetailPresentation.photoPreview.toggled == .focus)
        #expect(DetailPresentation.focus.toggled == .photoPreview)
        #expect(DetailPresentation.grid.toggled == .photoPreview)

        #expect(
            DetailPresentation.photoPreview.released(translation: -135, contentWidth: 900) == .focus
        )
        #expect(
            DetailPresentation.photoPreview.released(translation: 135, contentWidth: 900) == .grid)
        for distance in [-134.0, -20, 0, 20, 134] {
            #expect(
                DetailPresentation.photoPreview.released(translation: distance, contentWidth: 900)
                    == .photoPreview)
        }
        #expect(
            DetailPresentation.photoPreview.released(translation: -150, contentWidth: 1200)
                == .photoPreview)
        #expect(
            DetailPresentation.photoPreview.released(translation: -180, contentWidth: 1200)
                == .focus)
        #expect(
            DetailPresentation.photoPreview.released(translation: 100, contentWidth: 0)
                == .photoPreview)
    }

    @Test func availabilityPolicyCoversWideIPadExpandedDuoCompactAndFold() {
        let wideIPad = DetailPresentationPolicy(
            isRegularWidth: true, isDuoExpanded: false, isDuoCover: false,
            hasFoldRegion: false, availableWidth: 1024, availableHeight: 768)
        #expect(wideIPad.supportsPhotoPreview)
        #expect(wideIPad.effectivePresentation(for: .photoPreview) == .photoPreview)
        #expect(wideIPad.effectivePresentation(for: .focus) == .focus)

        let narrowIPad = DetailPresentationPolicy(
            isRegularWidth: true, isDuoExpanded: false, isDuoCover: false,
            hasFoldRegion: false, availableWidth: 500, availableHeight: 768)
        #expect(!narrowIPad.supportsPhotoPreview)
        #expect(narrowIPad.effectivePresentation(for: .photoPreview) == .focus)

        let compactWindow = DetailPresentationPolicy(
            isRegularWidth: false, isDuoExpanded: false, isDuoCover: false,
            hasFoldRegion: false, availableWidth: 393, availableHeight: 852)
        #expect(!compactWindow.supportsPhotoPreview)
        #expect(compactWindow.effectivePresentation(for: .photoPreview) == .focus)

        let duoCover = DetailPresentationPolicy(
            isRegularWidth: false, isDuoExpanded: false, isDuoCover: true,
            hasFoldRegion: false, availableWidth: 402, availableHeight: 874)
        #expect(!duoCover.supportsPhotoPreview)
        #expect(duoCover.effectivePresentation(for: .photoPreview) == .focus)

        let duoExpandedLandscape = DetailPresentationPolicy(
            isRegularWidth: true, isDuoExpanded: true, isDuoCover: false,
            hasFoldRegion: true, availableWidth: 870, availableHeight: 678)
        #expect(duoExpandedLandscape.supportsPhotoPreview)
        #expect(duoExpandedLandscape.effectivePresentation(for: .photoPreview) == .photoPreview)

        let duoExpandedPortraitFold = DetailPresentationPolicy(
            isRegularWidth: true, isDuoExpanded: true, isDuoCover: false,
            hasFoldRegion: true, availableWidth: 678, availableHeight: 870)
        #expect(duoExpandedPortraitFold.supportsPhotoPreview)
        #expect(duoExpandedPortraitFold.effectivePresentation(for: .photoPreview) == .photoPreview)

        // Ordinary Max/Plus iPhones report regular horizontal size class in landscape, but must
        // always enter Focus View rather than 30/70 Photo Preview.
        let maxIPhoneLandscape = DetailPresentationPolicy(
            isRegularWidth: true, isPhone: true, isDuoExpanded: false, isDuoCover: false,
            hasFoldRegion: false, availableWidth: 932, availableHeight: 430)
        #expect(!maxIPhoneLandscape.supportsPhotoPreview)
        #expect(maxIPhoneLandscape.effectivePresentation(for: .photoPreview) == .focus)
        #expect(maxIPhoneLandscape.effectivePresentation(for: .focus) == .focus)
        #expect(maxIPhoneLandscape.effectivePresentation(for: .grid) == .grid)

        let compactIPhoneLandscape = DetailPresentationPolicy(
            isRegularWidth: false, isPhone: true, isDuoExpanded: false, isDuoCover: false,
            hasFoldRegion: false, availableWidth: 852, availableHeight: 393)
        #expect(!compactIPhoneLandscape.supportsPhotoPreview)
        #expect(compactIPhoneLandscape.effectivePresentation(for: .photoPreview) == .focus)

        let duoExpandedWithPhoneIdiom = DetailPresentationPolicy(
            isRegularWidth: true, isPhone: true, isDuoExpanded: true, isDuoCover: false,
            hasFoldRegion: true, availableWidth: 870, availableHeight: 678)
        #expect(duoExpandedWithPhoneIdiom.supportsPhotoPreview)
        #expect(
            duoExpandedWithPhoneIdiom.effectivePresentation(for: .photoPreview) == .photoPreview)
    }
}
