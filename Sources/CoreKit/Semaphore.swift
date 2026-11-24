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
    public func tryAcquire() -> Bool {
        available.withLock { available in
            if available == 0 {
                return false
            }
            available -= 1
            return true
        }
    }

    /// Gives a permit back. Call it once for every `tryAcquire()` that returned true.
    public func release() {
        available.withLock { $0 += 1 }
    }
}
