import Foundation

/// A cancellable job that can be executed on a CFRunLoop.
/// Inspired by AeroSpace's RunLoopJob for managing AX operations.
final class RunLoopJob: Sendable {
    // Thread-safe cancellation flag using atomic operations
    nonisolated(unsafe) private var _isCancelled: Int32 = 0

    var isCancelled: Bool { _isCancelled == 1 }

    func cancel() {
        while !isCancelled {
            OSAtomicCompareAndSwapInt(0, 1, &_isCancelled)
        }
    }

    static let cancelled: RunLoopJob = RunLoopJob().also { $0.cancel() }

    func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}

// MARK: - Utility Extension

extension RunLoopJob {
    /// Allows chaining configuration
    func also(_ block: (RunLoopJob) -> Void) -> RunLoopJob {
        block(self)
        return self
    }
}
