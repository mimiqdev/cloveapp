import CloveCore
import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Clove

@MainActor
struct GridPhotoCellTests {
    @Test func coverCellLoadsPeekingMembersAsynchronouslyAndCancelsOnReuse() async throws {
        let cover = photo("MMQ02678")
        let second = photo("MMQ02679")
        let third = photo("MMQ02681")
        let fourth = photo("MMQ02682")

        let source = RecordingThumbnailSource(suspended: [second, third])
        let cell = GridPhotoCell(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let item = coverItem(cover: cover, peeking: [second, third])

        cell.configure(
            with: item, isSelected: false, isSelecting: false, thumbnails: source, theme: .light,
            onOpenGroup: { _ in })

        try await waitUntil {
            Set(source.startedPhotos) == Set([cover, second, third])
        }
        #expect(source.priorities[second] == .visible)
        #expect(source.priorities[third] == .visible)

        // Updating peeking members for the same cover cancels obsolete tasks and loads the new ID.
        let updated = coverItem(cover: cover, peeking: [second, fourth])
        cell.configure(
            with: updated, isSelected: false, isSelecting: false, thumbnails: source, theme: .light,
            onOpenGroup: { _ in })

        try await waitUntil {
            source.cancelledPhotos.contains(third) && source.startedPhotos.contains(fourth)
        }

        // Reuse cancels all remaining in-flight peeking requests.
        cell.prepareForReuse()
        try await waitUntil {
            source.cancelledPhotos.contains(second)
        }
        source.resumeAll()
    }

    @Test func coverCellRetriesDeferredPeekingThumbnails() async throws {
        let cover = photo("MMQ02678")
        let second = photo("MMQ02679")
        let source = RecordingThumbnailSource(deferredOnce: [second])
        let cell = GridPhotoCell(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        defer { cell.prepareForReuse() }

        cell.configure(
            with: coverItem(cover: cover, peeking: [second]), isSelected: false,
            isSelecting: false, thumbnails: source, theme: .light, onOpenGroup: { _ in })

        try await waitUntil {
            source.requestCounts[second, default: 0] >= 2
        }
    }

    @Test func warmCoverCellBuildsHostingConfigurationOnceWithoutAsyncRequests() async throws {
        let cover = photo("MMQ02678")
        let second = photo("MMQ02679")
        let third = photo("MMQ02681")

        let source = RecordingThumbnailSource(cached: [
            cover: .image(RecordingThumbnailSource.stubImage),
            second: .image(RecordingThumbnailSource.stubImage),
            third: .image(RecordingThumbnailSource.stubImage),
        ])
        let cell = GridPhotoCell(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        defer { cell.prepareForReuse() }

        cell.configure(
            with: coverItem(cover: cover, peeking: [second, third]), isSelected: false,
            isSelecting: false, thumbnails: source, theme: .light, onOpenGroup: { _ in })
        cell.resumeThumbnail(using: source)

        #expect(cell.hostingConfigurationCount == 1)
        #expect(source.startedPhotos.isEmpty)
        #expect(cell.contentConfiguration != nil)
    }

    private func coverItem(cover: PhotoIdentity, peeking: [PhotoIdentity]) -> GridCellItem {
        let gridPhoto = GridPhoto(
            id: cover, fileName: "\(cover.stem).ARW", time: .unavailable, marks: PhotoMarks())
        let group = GroupID(rawValue: "burst-test")
        return GridCellItem(
            id: .group(group), photo: gridPhoto,
            group: GridCellItem.GroupMark(
                id: group, count: peeking.count + 1, showsCount: true, isCover: true,
                peekingPhotos: peeking),
            isDimmed: false)
    }

    private func photo(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(
            folderID: FolderIdentity(rawValue: "test"), relativeFolderPath: "", stem: stem)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3), condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline {
                Issue.record("timed out waiting for GridPhotoCell thumbnail condition")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class RecordingThumbnailSource: GridThumbnailSource {
    private let cached: [PhotoIdentity: GridThumbnailOutcome]
    private let suspended: Set<PhotoIdentity>
    private var deferredOnce: Set<PhotoIdentity>
    private var continuations: [PhotoIdentity: CheckedContinuation<GridThumbnailOutcome, Never>] =
        [:]

    var startedPhotos: [PhotoIdentity] = []
    var priorities: [PhotoIdentity: GridThumbnailPriority] = [:]
    var cancelledPhotos: Set<PhotoIdentity> = []
    var requestCounts: [PhotoIdentity: Int] = [:]

    init(
        cached: [PhotoIdentity: GridThumbnailOutcome] = [:],
        suspended: Set<PhotoIdentity> = [], deferredOnce: Set<PhotoIdentity> = []
    ) {
        self.cached = cached
        self.suspended = suspended
        self.deferredOnce = deferredOnce
    }

    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? { cached[photo] }

    func companions(for photo: PhotoIdentity) -> GridCompanions { GridCompanions() }

    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority) async
        -> GridThumbnailOutcome
    {
        startedPhotos.append(photo)
        priorities[photo] = priority
        requestCounts[photo, default: 0] += 1

        if deferredOnce.remove(photo) != nil {
            return .deferred
        }
        if suspended.contains(photo) {
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    continuations[photo] = continuation
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelledPhotos.insert(photo)
                    self?.continuations.removeValue(forKey: photo)?.resume(returning: .deferred)
                }
            }
        }
        return .image(Self.stubImage)
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending.values {
            continuation.resume(returning: .image(Self.stubImage))
        }
    }

    static let stubImage: CGImage = {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()!
    }()
}
