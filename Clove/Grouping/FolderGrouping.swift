import CloveCore
import CloveImaging
import Foundation

/// One open folder's similar groups: C9's two stages over I3's features (PRD P0-11, G1's Grouping
/// row).
///
/// The folder library owns one of these while a folder is open, and nothing else in the app
/// reaches into grouping:
///
/// - ``begin(photos:revision:enabled:)`` runs step 2 and publishes its result — the cache's
///   finished groups when they still match — before the library reports the scan finished
///   (PRD P0-11).
/// - The background pass asks I3 for the features of the photos a group can form from, on its own
///   low-priority workers and through the grid's preview cache, then applies one refinement pass
///   (PRD Similar groups step 3). It never touches the grid's thumbnail workers or queue, so
///   features cannot delay a visible cell (G1 preview and scheduling rows).
/// - Every file read runs inside the folder's C11 session as admitted work, and ``close()``
///   cancels queued features and waits for a preview read in flight, so the folder's scope is
///   never released under one (G1 folder access).
///
/// C9's thresholds and rules stay in `CloveCore`; this type only supplies the inputs and maps the
/// published result to what the grid reads.
@MainActor
final class FolderGrouping {
    /// The folder's durable key, also the identity I3 cancels its work by (PRD P0-01, P0-11).
    private let folder: FolderIdentity
    /// The session that holds the folder's C11 scope while features read its files.
    private let session: FolderAccessSession
    /// C9's grouper: the time stage, the boundary decisions and the group cache.
    private let grouping: SimilarGrouping
    /// I3's feature pipeline, on its own workers and cache.
    private let features: ImageFeaturePipeline
    /// The source that answers C9's boundary questions from I3's settled features.
    private let similarity: PhotoFeatureSimilarity<ImageFeatures>
    /// The open folder's scanned sets, so a feature request reads a photo's primary file
    /// (G1 decision 1, PRD P0-11).
    private let sets: @MainActor (PhotoIdentity) -> PhotoSet?
    /// Where each published result goes: the library turns it into its stream update (P0-11).
    private let publish: @MainActor ([BrowsingGroup]) -> Void
    /// Presentation only: whether the visual pass still has work (handoff Opening).
    private let analysisChanged: @MainActor (Bool) -> Void

    /// The folder's photos as grouping receives them, replaced by Run again (PRD P0-11).
    private var inputs: [GroupingPhoto] = []
    /// The caller's cache token for these inputs, replaced with them (PRD Similar groups rules).
    private var revision = GroupingInputRevision(rawValue: "")
    /// C12's similar-groups setting for this folder (PRD P0-11).
    private var enabled = true
    /// Whether the folder ended, so a pass that resumes late starts nothing (G1 folder access).
    private var isClosed = false
    /// Whether ``begin(photos:revision:enabled:)`` installed this folder's input, so Run again
    /// and a setting change only act on a grouping that has started (PRD P0-11).
    private var hasBegun = false
    /// The result the library last received, so an unchanged publication stays quiet.
    private var published: [BrowsingGroup] = []
    /// The background feature and refinement pass, cancelled by a new run or by closing.
    private var analysisTask: Task<Void, Never>?
    /// The last queued run, so two Run again taps or a setting change cannot overlap (P0-11).
    private var transition: Task<Void, Never>?
    /// The grouper's published results, so a refinement reaches the grid (PRD P0-11).
    private var updatesTask: Task<Void, Never>?

    /// The feature pipeline's part of the group cache's token (PRD Similar groups rules).
    ///
    /// C9's fingerprint covers the photos, their times, bodies and names; the folder library adds
    /// each photo set's file revision to this token, so a changed file or a changed feature
    /// pipeline groups again instead of restoring older groups (G1's Grouping row).
    static let featureRevision = "preview:400|feature:2"

    /// Builds one folder's grouping over its caches, sets and publication.
    ///
    /// - Parameters:
    ///   - cache: C9's per-folder group cache in Application Support (PRD Similar groups rules).
    ///   - featureCache: I3's feature cache, in the app's Caches directory.
    ///   - previewCache: I1's thumbnail cache, shared so a feature reuses the preview the grid
    ///     already extracted and leaves its own read behind for the grid (G1 preview row).
    init(
        folder: FolderIdentity,
        session: FolderAccessSession,
        cache: SimilarGroupsCache,
        featureCache: ImageFeatureCache,
        previewCache: ThumbnailCache,
        sets: @escaping @MainActor (PhotoIdentity) -> PhotoSet?,
        publish: @escaping @MainActor ([BrowsingGroup]) -> Void,
        analysisChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.folder = folder
        self.session = session
        self.sets = sets
        self.publish = publish
        self.analysisChanged = analysisChanged
        // I3's record is the opaque feature both kinds answer with; C9 decides what a distance
        // means, so this only names the kind and never compares it with a threshold.
        let similarity = PhotoFeatureSimilarity<ImageFeatures> { left, right in
            switch left.distance(to: right) {
            case .visionPrint(let distance)?:
                return .vision(distance: Float(distance))
            case .differenceHash(let bits)?:
                return .differenceHash(distance: bits)
            case nil:
                return nil
            }
        }
        self.similarity = similarity
        self.grouping = SimilarGrouping(similarity: similarity, cache: cache)
        self.features = ImageFeaturePipeline(
            cache: featureCache, sharedPreviewCache: previewCache)
    }

    /// Runs step 2 for the folder and publishes it (PRD Similar groups steps 1–2, P0-11).
    ///
    /// It returns once the time-only groups — or the cache's finished result — are published, so
    /// the library can report the scan finished knowing the folder's groups exist. The
    /// refinement that needs features keeps running afterwards.
    func begin(
        photos: [GroupingPhoto], revision: GroupingInputRevision, enabled: Bool
    ) async {
        inputs = photos
        self.revision = revision
        self.enabled = enabled
        hasBegun = true
        await run(reusingCache: true)
    }

    /// Runs grouping again from the folder's current photos with the cache bypassed (P0-11).
    ///
    /// A folder whose first pass has not started yet ignores this: its input arrives with
    /// ``begin(photos:revision:enabled:)``, which the library calls once the scan finishes.
    func runAgain(photos: [GroupingPhoto]) async {
        guard hasBegun else { return }
        inputs = photos
        await run(reusingCache: false)
    }

    /// Applies the similar-groups setting to the open folder (PRD P0-11, `AppSettings`).
    ///
    /// Turning it off publishes no groups and stops feature work; the cache stays as it was, so
    /// turning it back on shows the finished result at once. A folder whose first pass has not
    /// started yet ignores the change: its time stage reads the setting when it begins. The
    /// settings screen reaches this through the folder library's one call.
    func setEnabled(_ enabled: Bool, photos: [GroupingPhoto]) async {
        guard hasBegun, !isClosed, enabled != self.enabled else { return }
        inputs = photos
        self.enabled = enabled
        await run(reusingCache: true)
    }

    /// Stops the folder's grouping before its C11 session ends (G1 folder access).
    ///
    /// Queued feature work is dropped, a preview read already running may finish and is
    /// discarded, and the grouper's stream is removed; the caller can then release the scope.
    func close() async {
        isClosed = true
        let analysis = analysisTask
        analysisTask = nil
        let pending = transition
        transition = nil
        updatesTask?.cancel()
        updatesTask = nil
        analysis?.cancel()
        await features.close()
        await analysis?.value
        // A run that was waiting for its turn returns without publishing; the caller can then
        // release the folder's scope.
        await pending?.value
    }

    // MARK: - Running

    /// Runs step 2 and starts the background pass for the current inputs.
    ///
    /// Runs are serialized: a Run again or a setting change that arrives while another run is in
    /// flight waits for it, so no two runs can publish into one another or leave two feature
    /// passes queueing file work. A dropped folder's queued run returns without publishing.
    private func run(reusingCache: Bool) async {
        let earlier = transition
        let queued = Task { [weak self] in
            await earlier?.value
            guard let self, !self.isClosed else { return }
            await self.performRun(reusingCache: reusingCache)
        }
        transition = queued
        await queued.value
    }

    /// Runs step 2 once it is this run's turn, then starts the background pass.
    ///
    /// A pass this run replaces is cancelled and awaited before the grouper runs again, and the
    /// closed state is re-checked after every suspension, so a resuming run never publishes,
    /// observes or reads for a folder that ended meanwhile.
    private func performRun(reusingCache: Bool) async {
        let earlierAnalysis = analysisTask
        analysisTask = nil
        earlierAnalysis?.cancel()
        await earlierAnalysis?.value
        // Jobs the replaced pass queued before it stopped are dropped here, so the new pass
        // starts from an empty queue (G1 scheduling row).
        await features.cancel(folder: folder.rawValue)
        guard !isClosed else { return }
        await grouping.run(
            photos: inputs, revision: revision, similarGroupsEnabled: enabled,
            reuseCache: reusingCache)
        guard !isClosed else { return }
        // The grouper's own result, read here rather than waited for, so the caller's next step
        // runs after the first publication instead of racing it (PRD P0-14).
        let result = await grouping.current
        guard !isClosed else { return }
        adopt(result.browsingGroups)
        startUpdates()
        startAnalysis(needsAnalysis: result.analysis != .analyzed)
    }

    /// Watches the grouper's later results, so a refinement reaches the grid (PRD P0-11).
    ///
    /// The loop borrows `self` only for each publication: a stream lasts until ``close()``, so
    /// holding the folder strongly for its whole lifetime would keep a closed folder's grouping,
    /// pipeline and caches alive behind the observer.
    private func startUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            guard let stream = await self?.grouping.updates() else { return }
            for await result in stream {
                guard !Task.isCancelled else { return }
                self?.adopt(result.browsingGroups)
            }
        }
    }

    /// Publishes one result unless the library already has it.
    private func adopt(_ groups: [BrowsingGroup]) {
        guard groups != published else { return }
        published = groups
        publish(groups)
    }

    /// Starts the folder's feature and refinement pass (PRD Similar groups step 3).
    private func startAnalysis(needsAnalysis: Bool) {
        analysisTask?.cancel()
        analysisTask = nil
        guard enabled, !isClosed else {
            analysisChanged(false)
            return
        }
        analysisChanged(needsAnalysis)
        let candidates = GroupingFeatureCandidates.photos(in: inputs)
        analysisTask = Task { [weak self] in
            guard let self else { return }
            // The previous task is awaited before a new run. Cancellation therefore finishes
            // its own presentation before the replacement can report that it is running.
            defer { self.analysisChanged(false) }
            await self.analyse(candidates)
        }
    }

    /// Computes the candidates' features inside the folder's admitted work, then refines once
    /// (PRD Similar groups step 3, G1's scheduling and folder-access rows).
    ///
    /// The whole pass runs as admitted work, so ending the folder waits for a preview read rather
    /// than releasing the scope under it; ``close()`` finishes the pass early by closing the
    /// pipeline. One refinement pass covers the whole folder on purpose: C9 re-walks every
    /// unsettled boundary per call, so asking for a pass per feature would make the work grow
    /// with the square of the folder's photo count.
    private func analyse(_ candidates: [GroupingPhoto]) async {
        guard !isClosed, enabled else { return }
        await similarity.start(photos: candidates.map(\.id))
        let sets = sets
        var sources: [(photo: GroupingPhoto, url: URL)] = []
        for photo in candidates {
            guard let url = sets(photo.id)?.primary.url else {
                // A photo the folder no longer holds has no feature, so its boundaries split
                // (G1's Grouping row).
                await similarity.settle(.unavailable, for: photo.id)
                continue
            }
            sources.append((photo, url))
        }
        let similarity = similarity
        let features = features
        let folder = folder
        let previewPixels = PipelineGridThumbnails.targetPixels
        let admittedSources = sources
        do {
            try await session.withAdmittedWork {
                // The revision each request keys on is a file read, so it happens here too
                // (G1 folder access, I1's request identity).
                var byRequest: [ImageFeatureRequest: PhotoIdentity] = [:]
                for source in admittedSources {
                    // A cancelled pass must stop reading files, or a Run again or a lost folder
                    // would leave it queueing work behind the new state (G1 folder access).
                    guard !Task.isCancelled else { return }
                    guard let revision = try? ThumbnailRevision.read(from: source.url) else {
                        await similarity.settle(.unavailable, for: source.photo.id)
                        continue
                    }
                    let request = ImageFeatureRequest(
                        preview: ThumbnailRequest(
                            source: source.url, revision: revision, targetPixels: previewPixels,
                            locationIdentity: folder.rawValue))
                    byRequest[request] = source.photo.id
                }
                guard !Task.isCancelled else { return }
                for await result in await features.run(Array(byRequest.keys)) {
                    guard let photo = byRequest[result.request] else { continue }
                    switch result.outcome {
                    case .features(let values):
                        await similarity.settle(.features(values), for: photo)
                    case .unavailable:
                        await similarity.settle(.unavailable, for: photo)
                    }
                }
            }
        } catch {
            // The folder ended before its features could read a file, so nothing is settled.
            return
        }
        guard !Task.isCancelled else { return }
        await grouping.refine()
    }

    deinit {
        // A dropped grouping must not keep its background work alive; the pipeline itself is
        // closed by the library that owns it, which is the only path that releases a scope.
        analysisTask?.cancel()
        updatesTask?.cancel()
    }
}
