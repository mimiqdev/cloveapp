import Testing

@testable import CloveImaging

/// Keep synchronous image fixture generation and framework calls off the cooperative pool
/// (#146). Tests remain parallel, and child tasks retain the caller's executor preference.
struct ImageWorkTestScope: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        try await withTaskExecutorPreference(ImageWorkExecutor.current) {
            try await function()
        }
    }
}

extension Trait where Self == ImageWorkTestScope {
    static var imageWork: Self { Self() }
}
