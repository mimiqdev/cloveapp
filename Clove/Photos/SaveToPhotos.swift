import CloveCore
import Foundation
import Photos

enum PhotosAuthorizationState: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

enum PhotosSaveError: Error, Equatable, Sendable {
    case permissionDenied
    case folderUnavailable
    case writeFailed
}

struct PhotosSavePlan: Equatable, Sendable {
    let targetPhotoIDs: [PhotoIdentity]
    let fileURLs: [URL]
    let skippedRawCount: Int
    let missingCount: Int

    var eligibleCount: Int { fileURLs.count }
    var totalSelectedCount: Int { eligibleCount + skippedRawCount }
    var isEmpty: Bool { targetPhotoIDs.isEmpty }
    var hasSkippedRawOnly: Bool { skippedRawCount > 0 }
    var hasOnlyRaw: Bool { eligibleCount == 0 && skippedRawCount > 0 }

    /// Resolves at most one existing JPEG or HEIF file per visible selected photo.
    /// RAW-only sets are counted in ``skippedRawCount`` and never decoded or re-encoded.
    static func resolve(
        targets: [GridPhoto],
        scannedSet: (PhotoIdentity) -> ScannedPhotoSet?
    ) -> PhotosSavePlan {
        var targetPhotoIDs: [PhotoIdentity] = []
        var fileURLs: [URL] = []
        var skippedRawCount = 0
        var missingCount = 0

        targetPhotoIDs.reserveCapacity(targets.count)
        fileURLs.reserveCapacity(targets.count)

        for photo in targets {
            targetPhotoIDs.append(photo.id)
            guard let photoSet = scannedSet(photo.id)?.photoSet else {
                missingCount += 1
                continue
            }
            switch photoSet.primary.format {
            case .jpeg, .heif:
                fileURLs.append(photoSet.primary.url)
            case .raw:
                if let companion = photoSet.jpegCompanion ?? photoSet.heifCompanion {
                    fileURLs.append(companion.url)
                } else {
                    skippedRawCount += 1
                }
            }
        }

        return PhotosSavePlan(
            targetPhotoIDs: targetPhotoIDs,
            fileURLs: fileURLs,
            skippedRawCount: skippedRawCount,
            missingCount: missingCount
        )
    }
}

enum PhotosSaveResult: Equatable, Sendable {
    case saved(eligibleCount: Int, skippedRawCount: Int)
    case failed(PhotosSaveError)
}

enum PhotosSaveToastMessage: Equatable, Sendable {
    case saved(savedCount: Int, skippedRawCount: Int)
    case permissionDenied
    case failed

    func localizedText(language: ResolvedAppLanguage) -> String {
        switch self {
        case .saved(let savedCount, let skippedRawCount):
            let base = AppLocalization.format(
                "Saved %lld photos to Photos", language: language, Int64(savedCount))
            if skippedRawCount > 0 {
                let skipped = AppLocalization.format(
                    "%lld RAW skipped", language: language, Int64(skippedRawCount))
                return AppLocalization.format("%@ · %@", language: language, base, skipped)
            }
            return base
        case .permissionDenied:
            return AppLocalization.string(
                "Allow Photos access in Settings to save photos.", language: language)
        case .failed:
            return AppLocalization.string("Couldn't save to Photos.", language: language)
        }
    }
}

protocol PhotosLibrarySaving: Sendable {
    func authorizationStatus() -> PhotosAuthorizationState
    func requestAddOnlyAuthorization() async -> PhotosAuthorizationState
    func savePhotos(fileURLs: [URL]) async throws
}

struct SystemPhotosLibrarySaver: PhotosLibrarySaving {
    func authorizationStatus() -> PhotosAuthorizationState {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    func requestAddOnlyAuthorization() async -> PhotosAuthorizationState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return Self.map(status)
    }

    func savePhotos(fileURLs: [URL]) async throws {
        guard !fileURLs.isEmpty else { return }

        let status: PhotosAuthorizationState
        switch authorizationStatus() {
        case .authorized:
            status = .authorized
        case .notDetermined:
            status = await requestAddOnlyAuthorization()
        case .denied:
            status = .denied
        }

        guard status == .authorized else {
            throw PhotosSaveError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in fileURLs {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: url, options: nil)
                }
            }
        } catch let error as PHPhotosError {
            switch error.code {
            case .accessUserDenied, .accessRestricted:
                throw PhotosSaveError.permissionDenied
            default:
                throw PhotosSaveError.writeFailed
            }
        } catch {
            throw PhotosSaveError.writeFailed
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotosAuthorizationState {
        switch status {
        case .authorized, .limited:
            .authorized
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }
}
