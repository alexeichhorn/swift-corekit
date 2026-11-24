import Synchronization

/// A fixed number of permits that tasks take and give back, to limit how much runs at once.
///
/// ```swift
/// let downloads = Semaphore(permits: 4)
///
/// guard downloads.tryAcquire() else { return }
/// Task {
///     defer { downloads.release() }
///     try await download(url)
/// }
/// ```
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

    public nonisolated(nonsending) func withPermitIfAvailable<Result, Failure: Error>(
        _ body: nonisolated(nonsending) () async throws(Failure) -> Result
    ) async throws(Failure) -> Result? {
        guard let permit = tryAcquire() else { return nil }
        defer { permit.release() }
        return try await body()
    }

    public final class Permit: Sendable {
        private let semaphore: Semaphore
        private let released = Atomic(false)

        fileprivate init(semaphore: Semaphore) {
            self.semaphore = semaphore
        }

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
