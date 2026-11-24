# CoreKit

Small building blocks for Swift backends: JSON schemas and validation from Swift types, typed environment
configuration, retries and timeouts, ordered JSON, compact logging, an HTTP client without surprises, and
FastAPI-style routes with an OpenAPI document on Hummingbird 2.

The package is being built; its guides arrive feature by feature.

## Installation

```swift
.package(url: "https://github.com/alexeichhorn/swift-corekit.git", branch: "main")
```

```swift
.product(name: "CoreKit", package: "swift-corekit")
```

## Secrets

```swift
let apiKey = Secret("sk-live-123")
print(apiKey)               // <redacted>
client.authorize(apiKey.exposedValue)
```

A `Secret` prints as `<redacted>` everywhere: `print`, string interpolation, `String(reflecting:)` and `dump`. Read
the value with `exposedValue`, only where it is handed to its consumer.

## Error context

```swift
let orders = try await withContext("failed to load orders") { try await repository.list() }

guard !orders.isEmpty else { throw ContextError("no orders for \(user)") }

print(errorDescription(error))  // failed to load orders: db query error: connection closed
```

- `withContext` wraps whatever the closure throws in a `ContextError` that says what was being done. Its description
  is the whole chain, outermost first, joined with `: `.
- `errorDescription` is the text to log or store for any error. It uses an error's debug description when there is
  one, because some errors, PostgresNIO's among them, keep the details out of the plain description.

## Retry and timeout

```swift
struct RateLimited: Retryable {
    var isRetryable: Bool { true }
}

@Retry(maxRetries: 4, initialDelay: .milliseconds(250))
func chargeOrder(_ order: Order) async throws -> Receipt { ... }

@Retry(maxRetries: 1, initialDelay: .seconds(1), jitter: false, timeout: .seconds(120))
func sendReport(_ report: Report) async throws -> Response { ... }

@Timeout(.seconds(30))
func fetchPage(_ url: URL) async throws -> Page { ... }

// The functions behind the macros:
let page = try await retry(maxRetries: 2) { try await withTimeout(.seconds(30)) { try await load(url) } }
```

- Only errors that conform to `Retryable` and return `isRetryable == true` are retried; every other error is rethrown
  at once. `maxRetries` counts the retries after the first attempt.
- The wait before the first retry is `initialDelay`, and each later one is `exponentialBase` times the one before,
  capped at `maxDelay`. With `jitter` the actual wait is random between zero and that delay. Defaults: 20 retries,
  1 second, base 2, 180 seconds, jitter on.
- An error can say how long to wait itself: give it a `retryAfter` (for example from a `Retry-After` header), and that
  wait replaces the backoff for that retry.
- A timeout cancels the work and throws `TimeoutError`, which is retryable. `timeout:` on `@Retry` limits each attempt.
  Cancellation is cooperative: work that ignores it is waited for.
- Both macros need an `async throws` function. Swift applies only one body macro per function, so combining them is a
  compile error; use `@Retry(..., timeout:)`.
- With a timeout the body runs in a child task, so the function's parameters and result, and `self` in a method, must
  be `Sendable`. `@Retry` without `timeout:` has no such requirement.

## Strings and bytes

`text.prefix(bytes: 500)` cuts a string to at most that many bytes of UTF-8 without splitting a code point, for limits
that count bytes.

`text.trimmingWhitespace()` removes the whitespace at both ends, where whitespace is Unicode's `White_Space` property.
Use it where the result is hashed or compared with a value another system trimmed.

`bytes.hex` writes any sequence of bytes, such as a hash, as lowercase hexadecimal.

`date.rfc3339` writes a date in UTC with a numeric zone, `2026-11-14T12:34:56+00:00`, and a fraction of three or six
digits only when the date has one.

## Collections

`products.sorted(by: \.name)` sorts by a property in ascending order, in place of a comparison closure;
`sorted(by: \.name, descending: true)` sorts the other way.

`orders.uniqued(on: \.userID)` keeps the first element of each key, in the order of the elements.

`names[safe: 3]` is the element at an index, or `nil` when the collection has none there, where `names[3]` would crash.

## Numbers and durations

`value.dividedRoundingUp(by: divisor)` divides and rounds up, and `value.roundedUp(toMultipleOf: step)` gives the next
multiple of `step`. Both work on any integer type and take a positive divisor or step.

`duration.milliseconds` gives a `Duration` in whole milliseconds, for example for a `duration_ms` log field:
`(ContinuousClock.now - start).milliseconds`.

## Concurrency

```swift
let pages = try await urls.concurrentMap(maxConcurrency: 4) { try await fetch($0) }
```

`concurrentMap` runs the closure for every element with at most `maxConcurrency` running at once; without it all run
at once. The results come back in the order of the elements, and the first error cancels the rest. A closure that
cannot throw needs no `try`.

```swift
let downloads = Semaphore(permits: 4)

guard downloads.tryAcquire() else { return }
Task {
    defer { downloads.release() }
    try await download(url)
}
```

`Semaphore` limits work that is not one collection, such as tasks started one by one: `tryAcquire()` takes a permit
when one is free and never waits, and `release()` gives it back.

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE) at your option.
