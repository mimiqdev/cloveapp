import Dispatch

/// Image decoders and cache I/O can wait inside system frameworks. Run that work on Dispatch
/// threads while keeping Swift task cancellation and suspension, including across async readers.
/// Pipeline admission still bounds how many image jobs can run at once.
final class ImageWorkExecutor: TaskExecutor {
    static let userInitiated = ImageWorkExecutor(qos: .userInitiated)
    static let utility = ImageWorkExecutor(qos: .utility)
    static var current: ImageWorkExecutor {
        Task.currentPriority <= .utility ? utility : userInitiated
    }

    private let queue: DispatchQueue

    private init(qos: DispatchQoS) {
        queue = DispatchQueue(
            label: "Clove.ImageWork.\(qos.qosClass)", qos: qos,
            attributes: .concurrent, autoreleaseFrequency: .workItem)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async {
            job.runSynchronously(on: self.asUnownedTaskExecutor())
        }
    }
}
