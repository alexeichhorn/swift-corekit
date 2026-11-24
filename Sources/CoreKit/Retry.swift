/// An error that says whether the operation that threw it is worth another attempt.
public protocol Retryable: Error {
    var isRetryable: Bool { get }

    /// How long to wait before the next attempt when the failure itself says so, such as a `Retry-After` header;
    /// `nil` by default, which leaves the wait to the backoff.
    var retryAfter: Duration? { get }
}

extension Retryable {
    public var retryAfter: Duration? { nil }
}

/// Thrown when the time given to ``withTimeout(_:clock:operation:)`` or `@Timeout` runs out.
public struct TimeoutError: Retryable {
    public var isRetryable: Bool { true }

    public init() {}
}

/// Runs `operation` again when it throws a ``Retryable`` error whose `isRetryable` is true, at most `maxRetries` times
/// after the first attempt. Any other error is rethrown at once.
///
/// The wait before the first retry is `initialDelay`; every later one is `exponentialBase` times the one before, and
/// none exceeds `maxDelay`. With `jitter` the actual wait is random between zero and that delay. An error with a
/// `retryAfter` is waited for exactly that long instead, and leaves the backoff where it is.
nonisolated(nonsending) public func retry<Value>(
    maxRetries: Int = 20,
    initialDelay: Duration = .seconds(1),
    exponentialBase: Int = 2,
    maxDelay: Duration = .seconds(180),
    jitter: Bool = true,
    clock: any Clock<Duration> = ContinuousClock(),
    operation: () async throws -> Value
) async throws -> Value {
    var delay = min(initialDelay, maxDelay)
    var retryCount = 0
    while true {
        do {
            return try await operation()
        } catch {
            guard let retryable = error as? any Retryable, retryable.isRetryable, retryCount < maxRetries else { throw error }
            // A retry without a wait would otherwise never notice the cancellation.
            try Task.checkCancellation()
            retryCount += 1
            if let retryAfter = retryable.retryAfter {
                if retryAfter > .zero { try await clock.sleep(for: retryAfter) }
                continue
            }
            let wait = jitter ? delay * Double.random(in: 0...1) : delay
            if wait > .zero { try await clock.sleep(for: wait) }
            delay = min(delay * exponentialBase, maxDelay)
        }
    }
}

/// ``retry(maxRetries:initialDelay:exponentialBase:maxDelay:jitter:clock:operation:)`` with every attempt limited to
/// `timeout`; an attempt that times out is retried.
///
/// Attempts run in a child task, so `operation` and its result must be `Sendable`.
public func retry<Value: Sendable>(
    maxRetries: Int = 20,
    initialDelay: Duration = .seconds(1),
    exponentialBase: Int = 2,
    maxDelay: Duration = .seconds(180),
    jitter: Bool = true,
    timeout: Duration,
    clock: any Clock<Duration> = ContinuousClock(),
    operation: @Sendable () async throws -> Value
) async throws -> Value {
    try await retry(
        maxRetries: maxRetries,
        initialDelay: initialDelay,
        exponentialBase: exponentialBase,
        maxDelay: maxDelay,
        jitter: jitter,
        clock: clock
    ) {
        try await withTimeout(timeout, clock: clock, operation: operation)
    }
}

/// Returns the result of `operation`, or cancels it and throws ``TimeoutError`` when it takes longer than `timeout`.
///
/// Cancellation is cooperative: an operation that ignores it keeps this function waiting until it finishes.
/// `operation` runs in a child task, so it and its result must be `Sendable`.
public func withTimeout<Value: Sendable>(
    _ timeout: Duration,
    clock: any Clock<Duration> = ContinuousClock(),
    operation: @Sendable () async throws -> Value
) async throws -> Value {
    try await withoutActuallyEscaping(operation) { operation in
        try await withThrowingTaskGroup(of: Value.self) { group in
            defer { group.cancelAll() }
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(for: timeout)
                throw TimeoutError()
            }
            return try await group.next()!
        }
    }
}
