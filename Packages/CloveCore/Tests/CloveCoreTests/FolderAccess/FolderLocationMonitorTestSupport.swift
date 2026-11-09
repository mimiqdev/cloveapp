import Foundation
import Synchronization

import CloveCore

/// A presenter the test drives, standing in for `NSFilePresenter` callbacks.
final class ManualFolderChangePresenter: FolderChangePresenting, Sendable {
    struct State {
        var onChange: (@Sendable () -> Void)?
        var startCount = 0
        var stopCount = 0
        var isPresenting = false
    }

    private let state = Mutex(State())

    var startCount: Int { state.withLock { $0.startCount } }
    var stopCount: Int { state.withLock { $0.stopCount } }
    var isPresenting: Bool { state.withLock { $0.isPresenting } }

    func start(presenting url: URL, onChange: @escaping @Sendable () -> Void) {
        state.withLock {
            $0.onChange = onChange
            $0.startCount += 1
            $0.isPresenting = true
        }
    }

    func stop() {
        state.withLock {
            guard $0.isPresenting else { return }
            $0.isPresenting = false
            $0.onChange = nil
            $0.stopCount += 1
        }
    }

    func notifyChange() {
        let callback = state.withLock { $0.onChange }
        callback?()
    }
}

/// Collects connection losses reported by a monitor.
final class LossRecorder: Sendable {
    private let state = Mutex<[FolderLocationLoss]>([])

    var losses: [FolderLocationLoss] { state.withLock { $0 } }

    func record(_ loss: FolderLocationLoss) {
        state.withLock { $0.append(loss) }
    }
}
