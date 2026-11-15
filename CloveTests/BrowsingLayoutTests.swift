import CloveCore
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct BrowsingLayoutTests {
    @Test func widthChangesKeepTheFolderPhotoFilterAndSelection() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let photo = try #require(model.photos.last?.id)
        model.setFilter(.subfolder(photo.relativeFolderPath))
        model.toggleSelection(photo)
        model.openPhoto(photo)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: BrowseShell(browsing: model).environment(SettingsStore.sample))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        for route in [BrowserRoute.detail, .settings] {
            if route == .settings {
                model.back()
                model.showSettings()
            }
            let saved = model.state
            for width in [UIUserInterfaceSizeClass.regular, .compact, .regular] {
                host.traitOverrides.horizontalSizeClass = width
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                #expect(model.state == saved)
                #expect(model.filterTitle == photo.relativeFolderPath)
            }
        }
        model.back()
        #expect(model.state.route == .grid)
        #expect(model.state.currentPhoto == photo)
        #expect(model.state.selection == [photo])
        #expect(model.state.filter == .subfolder(photo.relativeFolderPath))
    }

    @Test func detailPresentationDefaultsToPhotoPreviewAndResetsAfterBack() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let first = try #require(model.photos.first?.id)
        let second = try #require(model.photos.dropFirst().first?.id)
        model.openPhoto(first)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(
            rootView: BrowseShell(browsing: model).environment(SettingsStore.sample))
        host.traitOverrides.horizontalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Regular wide iPad opens Photo Preview (grid collection view present).
        try await Task.sleep(for: .milliseconds(200))
        #expect(hasGridCollection(in: window))

        // Incidental compact transition falls back to Focus View, then restores Photo Preview.
        host.traitOverrides.horizontalSizeClass = .compact
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!hasGridCollection(in: window))

        host.traitOverrides.horizontalSizeClass = .regular
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(hasGridCollection(in: window))

        // Leaving detail and opening another photo starts in Photo Preview again.
        model.back()
        try await Task.sleep(for: .milliseconds(100))
        model.openPhoto(second)
        try await Task.sleep(for: .milliseconds(150))
        #expect(hasGridCollection(in: window))
    }

    private func hasGridCollection(in view: UIView) -> Bool {
        if view is UICollectionView { return true }
        return view.subviews.contains { hasGridCollection(in: $0) }
    }
}
