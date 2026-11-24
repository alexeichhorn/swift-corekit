import CoreKit
import Synchronization
import Testing

private struct Flaky: Retryable {
    let isRetryable: Bool
    var retryAfter: Duration?
}

private struct Broken: Error {}

/// Returns from every sleep at once and records how long it was asked to sleep.
private final class RecordingClock: Clock {
    let now = ContinuousClock.now
    let minimumResolution = Duration.zero
    let sleeps = Mutex<[Duration]>([])

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        sleeps.withLock { $0.append(now.duration(to: deadline)) }
    }
}

@Test func retryBacksOffUntilMaxRetries() async {
    let clock = RecordingClock()
    var attempts = 0
    await #expect(throws: Flaky.self) {
        try await retry(maxRetries: 4, initialDelay: .milliseconds(250), maxDelay: .seconds(1), jitter: false, clock: clock) {
            attempts += 1
            throw Flaky(isRetryable: true)
        }
    }
    #expect(attempts == 5)
    #expect(clock.sleeps.withLock { $0 } == [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(1)])

    let jitterClock = RecordingClock()
    await #expect(throws: Flaky.self) {
        try await retry(maxRetries: 3, clock: jitterClock) { throw Flaky(isRetryable: true) }
    }
    let jittered = jitterClock.sleeps.withLock { $0 }
    #expect(jittered.count == 3)
    #expect(zip(jittered, [1, 2, 4]).allSatisfy { $0 >= .zero && $0 <= .seconds($1) })
}

@Test func retryWaitsAsLongAsTheErrorAsks() async {
    let clock = RecordingClock()
    var attempts = 0
    await #expect(throws: Flaky.self) {
        try await retry(maxRetries: 3, initialDelay: .milliseconds(100), jitter: false, clock: clock) {
            attempts += 1
            throw Flaky(isRetryable: true, retryAfter: attempts == 2 ? .seconds(7) : nil)
        }
    }
    // The asked-for wait replaces one backoff step without using it up.
    #expect(clock.sleeps.withLock { $0 } == [.milliseconds(100), .seconds(7), .milliseconds(200)])
}

@Test func retryRethrowsOtherErrorsAtOnce() async {
    let clock = RecordingClock()
    var attempts = 0
    await #expect(throws: Flaky.self) {
        try await retry(clock: clock) {
            attempts += 1
            throw Flaky(isRetryable: false)
        }
    }
    await #expect(throws: Broken.self) {
        try await retry(clock: clock) {
            attempts += 1
            throw Broken()
        }
    }
    #expect(attempts == 2)
    #expect(clock.sleeps.withLock { $0 }.isEmpty)
}

@Test func withTimeoutReturnsInTimeOrThrows() async throws {
    #expect(try await withTimeout(.seconds(30)) { "done" } == "done")
    await #expect(throws: TimeoutError.self) {
        try await withTimeout(.milliseconds(20)) { try await Task.sleep(for: .seconds(60)) }
    }
}

/// Compiles the `@Retry` and `@Timeout` expansions in a `Sendable` class.
private final class PageClient: Sendable {
    let attempts = Mutex(0)

    /// The first attempt hangs.
    @Retry(maxRetries: 2, initialDelay: .zero, timeout: .milliseconds(100))
    func fetchPage(_ path: String) async throws -> String {
        let attempt = attempts.withLock { attempts in
            attempts += 1
            return attempts
        }
        if attempt == 1 { try await Task.sleep(for: .seconds(60)) }
        return "page at \(path)"
    }

    @Retry(maxRetries: 1, initialDelay: .zero)
    func failOnce() async throws {
        let attempt = attempts.withLock { attempts in
            attempts += 1
            return attempts
        }
        guard attempt > 1 else { throw Flaky(isRetryable: true) }
    }

    @Timeout(.milliseconds(20))
    func hang() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

@Test func retryRetriesAnAttemptThatTimesOut() async throws {
    let client = PageClient()
    #expect(try await client.fetchPage("/items") == "page at /items")
    #expect(client.attempts.withLock { $0 } == 2)

    try await PageClient().failOnce()
    await #expect(throws: TimeoutError.self) { try await client.hang() }
}
