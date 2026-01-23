import Foundation

/// Action wrapper for executing code on a specific thread's run loop
private final class RunLoopAction: NSObject, Sendable {
    private let _action: @Sendable (RunLoopJob) -> Void
    let job: RunLoopJob
    private let autoCheckCancelled: Bool

    init(job: RunLoopJob, autoCheckCancelled: Bool, _ action: @escaping @Sendable (RunLoopJob) -> Void) {
        self.job = job
        self.autoCheckCancelled = autoCheckCancelled
        _action = action
    }

    @objc func action() {
        if autoCheckCancelled && job.isCancelled { return }
        _action(job)
    }
}

extension Thread {
    /// Execute a closure asynchronously on this thread's run loop.
    /// Returns a RunLoopJob that can be used to cancel the operation.
    @discardableResult
    func runInLoopAsync(
        job: RunLoopJob = RunLoopJob(),
        autoCheckCancelled: Bool = true,
        _ body: @Sendable @escaping (RunLoopJob) -> Void
    ) -> RunLoopJob {
        let action = RunLoopAction(job: job, autoCheckCancelled: autoCheckCancelled, body)
        action.perform(#selector(action.action), on: self, with: nil, waitUntilDone: false)
        return job
    }

    /// Execute a closure on this thread's run loop and await its result.
    /// Supports cancellation via Swift's structured concurrency.
    func runInLoop<T: Sendable>(_ body: @Sendable @escaping (RunLoopJob) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let job = RunLoopJob()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.runInLoopAsync(job: job, autoCheckCancelled: false) { job in
                    do {
                        try job.checkCancellation()
                        cont.resume(returning: try body(job))
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}
