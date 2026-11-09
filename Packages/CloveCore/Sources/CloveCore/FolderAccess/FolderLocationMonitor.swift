import Foundation

/// Why a watched folder stopped being reachable (PRD P0-02; G1 folder access).
public struct FolderLocationLoss: Hashable, Sendable {
    /// The two explanations P0-02 lets the app distinguish.
    public enum Reason: String, Hashable, Sendable {
        /// The folder was on an external volume and that volume's root is gone (G1 folder access).
        case externalVolumeDisconnected
        /// The folder itself is gone or unreadable; not proof of a disconnect (G1 folder access).
        case locationUnavailable
    }

    /// The explanation to show for this loss.
    public let reason: Reason
    /// When the watch observed the loss.
    public let date: Date
    /// The reachability error, or nil when the system only said "not reachable" (S1).
    public let error: FolderErrorChain?

    /// Describes one observed loss; the monitor reports it once.
    public init(reason: Reason, date: Date, error: FolderErrorChain? = nil) {
        self.reason = reason
        self.date = date
        self.error = error
    }
}

/// Registers the file-presenter callback that watches a folder (G1 folder access).
///
/// Presenter callbacks are advisory: S1 saw none for an uncoordinated local deletion, so they
/// supplement the reachability poll rather than replacing it.
public protocol FolderChangePresenting: Sendable {
    /// Starts presenting `url`; `onChange` may arrive on any queue and only asks the watch to look.
    func start(presenting url: URL, onChange: @escaping @Sendable () -> Void)
    /// Removes the presenter, so no callback arrives after the watch stops.
    func stop()
}

/// Watches an open folder for a lost location while the app is in the foreground.
///
/// G1 folder access uses a 500 ms reachability poll plus a file presenter. The first failure reports
/// one `FolderLocationLoss` and stops the watch; stopping also removes the presenter and cancels the
/// timer. A missing folder is called a drive disconnect only when it was on an external volume and
/// that volume's root is gone. Provider calls can block, so the interval is not a deadline (S1).
public actor FolderLocationMonitor {
    private let rootURL: URL
    private let mediaType: FolderMediaType
    private let suppliedVolumeRootURL: URL?
    private let pollInterval: Duration
    private let reading: any FolderLocationReading
    private let presenting: any FolderChangePresenting
    private let now: @Sendable () -> Date

    private var volumeRootURL: URL?
    private var pollTask: Task<Void, Never>?
    private var onLoss: (@Sendable (FolderLocationLoss) -> Void)?
    private var hasReported = false

    /// Creates a monitor; the volume root is read from the folder unless the caller supplies one.
    public init(
        rootURL: URL,
        mediaType: FolderMediaType,
        volumeRootURL: URL? = nil,
        pollInterval: Duration = .milliseconds(500),
        reading: any FolderLocationReading = FileSystemLocationReader(),
        presenting: any FolderChangePresenting = SystemFolderChangePresenter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootURL = rootURL
        self.mediaType = mediaType
        self.suppliedVolumeRootURL = volumeRootURL
        self.pollInterval = pollInterval
        self.reading = reading
        self.presenting = presenting
        self.now = now
    }

    /// Whether the timer and presenter are active (G1 folder access).
    public var isWatching: Bool { pollTask != nil }

    /// Starts polling and presenter callbacks, replacing any earlier watch.
    ///
    /// The callback runs after the watch has stopped and must not wait on this monitor.
    public func start(reportingLossTo onLoss: @escaping @Sendable (FolderLocationLoss) -> Void) {
        stop()
        self.onLoss = onLoss
        hasReported = false
        volumeRootURL = suppliedVolumeRootURL ?? reading.facts(for: rootURL).volumeRootURL
        presenting.start(presenting: rootURL) { [weak self] in
            guard let self else { return }
            Task { await self.checkNow() }
        }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.checkNow()
            }
        }
    }

    /// Checks reachability now; the timer, presenter and a foreground return all use this.
    ///
    /// Only the first loss is reported, and it stops the watch.
    public func checkNow() {
        guard isWatching, !hasReported else { return }
        var chain: FolderErrorChain?
        var reachable = false
        var fresh = URL(fileURLWithPath: rootURL.path, isDirectory: true)
        fresh.removeAllCachedResourceValues()
        do {
            reachable = try fresh.checkResourceIsReachable()
        } catch {
            chain = FolderErrorChain(error)
        }
        guard !reachable else { return }
        let reason: FolderLocationLoss.Reason =
            mediaType == .externalDrive && volumeRootIsGone()
            ? .externalVolumeDisconnected : .locationUnavailable
        report(FolderLocationLoss(reason: reason, date: now(), error: chain))
    }

    /// Stops the watch: removes the presenter, cancels the timer and forgets the callback.
    public func stop() {
        presenting.stop()
        pollTask?.cancel()
        pollTask = nil
        onLoss = nil
    }

    private func report(_ loss: FolderLocationLoss) {
        hasReported = true
        let callback = onLoss
        stop()
        callback?(loss)
    }

    deinit {
        // A dropped monitor must not leave its presenter registered with the system.
        presenting.stop()
        pollTask?.cancel()
    }

    /// Whether the volume's root is gone; only a missing root supports "drive disconnected".
    private func volumeRootIsGone() -> Bool {
        guard let volumeRootURL else { return false }
        var fresh = URL(fileURLWithPath: volumeRootURL.path, isDirectory: true)
        fresh.removeAllCachedResourceValues()
        do {
            return try !fresh.checkResourceIsReachable()
        } catch {
            return FolderErrorChain(error).isLocationUnavailable
        }
    }
}

/// The system file presenter used by the disconnect watch (G1 folder access).
///
/// The presenter stores one immutable `Sendable` callback; the only mutable state is the
/// registration, protected by a lock. That is why the unchecked `Sendable` conformance is safe.
public final class SystemFolderChangePresenter: FolderChangePresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var presenter: FolderChangeFilePresenter?

    /// Creates a presenter registrar; it registers nothing until started.
    public init() {}

    /// Registers a presenter that asks the monitor to check the folder on any change.
    public func start(presenting url: URL, onChange: @escaping @Sendable () -> Void) {
        stop()
        let presenter = FolderChangeFilePresenter(url: url, onChange: onChange)
        lock.withLock { self.presenter = presenter }
        NSFileCoordinator.addFilePresenter(presenter)
    }

    /// Removes the registered presenter, if any.
    public func stop() {
        let existing = lock.withLock { () -> FolderChangeFilePresenter? in
            defer { presenter = nil }
            return presenter
        }
        if let existing { NSFileCoordinator.removeFilePresenter(existing) }
    }
}

/// The `NSFilePresenter` bridge; its callbacks only forward to the monitor's check (G1).
private final class FolderChangeFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    func presentedItemDidChange() {
        onChange()
    }

    func presentedSubitemDidChange(at url: URL) {
        onChange()
    }

    func presentedItemDidMove(to newURL: URL) {
        onChange()
    }

    func accommodatePresentedItemDeletion(
        completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        onChange()
        completionHandler(nil)
    }
}
