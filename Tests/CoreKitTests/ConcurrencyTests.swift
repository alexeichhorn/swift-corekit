import CoreKit
import Testing

private actor RunningCount {
    private var running = 0
    private(set) var highest = 0

    func enter() {
        running += 1
        highest = max(highest, running)
    }

    func leave() {
        running -= 1
    }
}

@Test func concurrentMapKeepsOrderAndRespectsItsLimit() async throws {
    let count = RunningCount()
    let doubled = try await (0..<20).concurrentMap(maxConcurrency: 3) { number in
        await count.enter()
        // Later elements finish first, so the order of the results is not the order of completion.
        try await Task.sleep(for: .milliseconds(20 - number))
        await count.leave()
        return number * 2
    }

    #expect(doubled == (0..<20).map { $0 * 2 })
    #expect(await count.highest == 3)

    // A transformation that cannot throw needs no `try`, and without a limit all run at once.
    let tripled = await (0..<5).concurrentMap { $0 * 3 }
    #expect(tripled == [0, 3, 6, 9, 12])

    struct Failed: Error {}
    await #expect(throws: Failed.self) {
        try await (0..<20).concurrentMap(maxConcurrency: 3) { number in
            if number == 5 { throw Failed() }
            return number
        }
    }
}

/// The transformations still running when one fails are cancelled, so the call ends without waiting for them.
@Test func concurrentMapCancelsTheRestOnTheFirstError() async {
    struct Failed: Error {}
    let started = ContinuousClock.now
    await #expect(throws: Failed.self) {
        try await (0..<4).concurrentMap { number in
            if number == 0 { throw Failed() }
            try await Task.sleep(for: .seconds(60))
            return number
        }
    }
    #expect(ContinuousClock.now - started < .seconds(10))
}

@Test func semaphoreHandsOutItsPermitsAndTakesThemBack() throws {
    let semaphore = Semaphore(permits: 2)

    let first = try #require(semaphore.tryAcquire())
    let second = try #require(semaphore.tryAcquire())
    #expect(semaphore.tryAcquire() == nil)
    #expect(semaphore.availablePermits == 0)

    // A permit goes back once, however often it is released.
    first.release()
    first.release()
    #expect(semaphore.availablePermits == 1)

    second.release()
    #expect(semaphore.availablePermits == 2)
}

@Test func semaphoreTakesBackAPermitNobodyReleased() {
    let semaphore = Semaphore(permits: 1)

    withExtendedLifetime(semaphore.tryAcquire()) { permit in
        #expect(permit != nil)
        #expect(semaphore.availablePermits == 0)
    }
    #expect(semaphore.availablePermits == 1)
}

@Test func semaphoreRunsABodyWithAPermitWhenOneIsFree() async throws {
    let semaphore = Semaphore(permits: 1)

    struct Failed: Error {}
    await #expect(throws: Failed.self) {
        try await semaphore.withPermitIfAvailable {
            #expect(semaphore.availablePermits == 0)
            throw Failed()
        }
    }
    #expect(semaphore.availablePermits == 1)

    let permit = try #require(semaphore.tryAcquire())
    let result = await semaphore.withPermitIfAvailable { "ran" }
    #expect(result == nil)
    permit.release()
}

/// Many tasks ask at once; no more than the permits may get one.
@Test func semaphoreNeverHandsOutMoreThanItsPermits() async {
    let semaphore = Semaphore(permits: 3)
    let permits = await (0..<200).concurrentMap { _ in semaphore.tryAcquire() }

    #expect(permits.count { $0 != nil } == 3)
}
