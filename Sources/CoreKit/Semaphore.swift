import Synchronization

/// A fixed number of permits that tasks take and give back, to limit how much runs at once.
///
/// ```swift
/// let downloads = Semaphore(permits: 4)
///
/// guard let permit = downloads.tryAcquire() else { return }
/// Task {
///     defer { permit.release() }
///     try await download(url)
/// }
/// ```
///
/// A permit goes back only to the semaphore it came from, and only once.
public final class Semaphore: Sendable {
    public let permits: Int
    private let available: Mutex<Int>

    public init(permits: Int) {
        self.permits = permits
        self.available = Mutex(permits)
    }

    /// The permits nobody holds right now.
    public var availablePermits: Int {
        available.withLock(\.self)
    }

    /// Takes a permit when one is free. Never waits.
    ///
    /// Keep the permit while the work runs and call ``Permit/release()`` when it ends.
    public func tryAcquire() -> Permit? {
        let acquired = available.withLock { available in
            if available == 0 {
                return false
            }
            available -= 1
            return true
        }
        return acquired ? Permit(semaphore: self) : nil
    }

    /// Takes a permit when one is free, runs `body` and gives the permit back, also when `body` throws.
    ///
    /// Returns `nil` without running `body` when no permit is free. Never waits. `body` runs on the caller's
    /// isolation.
    public nonisolated(nonsending) func withPermitIfAvailable<Result, Failure: Error>(
        _ body: nonisolated(nonsending) () async throws(Failure) -> Result
    ) async throws(Failure) -> Result? {
        guard let permit = tryAcquire() else { return nil }
        defer { permit.release() }
        return try await body()
    }

    /// A permit taken from a ``Semaphore``.
    ///
    /// The first ``release()`` gives it back; later calls do nothing. A permit nobody released goes back when it is
    /// deallocated. That is a backstop, not a scope guard: Swift may end an object's lifetime after its last use, so
    /// the permit could go back before the work it guards ends. Keep the permit and call ``release()``, or use
    /// ``Semaphore/withPermitIfAvailable(_:)``.
    public final class Permit: Sendable {
        private let semaphore: Semaphore
        private let released = Atomic(false)

        fileprivate init(semaphore: Semaphore) {
            self.semaphore = semaphore
        }

        /// Gives the permit back. Only the first call does.
        public func release() {
            if !released.exchange(true, ordering: .relaxed) {
                semaphore.available.withLock { $0 += 1 }
            }
        }

        deinit {
            release()
        }
    }
}
