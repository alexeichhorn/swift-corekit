# CoreKit

Small building blocks for Swift backends: JSON schemas and validation from Swift types, typed environment
configuration, retries and timeouts, ordered JSON, compact logging, an HTTP client without surprises, and
FastAPI-style routes with an OpenAPI document on Hummingbird 2.

## Installation

Requires Swift 6.4 and runs on macOS 15 or later and on Linux.

```swift
.package(url: "https://github.com/alexeichhorn/swift-corekit.git", branch: "main")
```

```swift
.product(name: "CoreKit", package: "swift-corekit")
.product(name: "CoreKitHummingbird", package: "swift-corekit")
.product(name: "CoreKitHTTPClient", package: "swift-corekit")
```

- `CoreKit`: `@Schema`, `@EnvConfig`, `@PublicInit`, `@Retry`/`@Timeout`, ordered JSON, logging and small helpers. No
  HTTP framework.
- `CoreKitHummingbird`: routers and `@GET`/`@POST` handler functions on Hummingbird 2, with `/openapi.json` and
  `/docs` derived from the handlers.
- `CoreKitHTTPClient`: a plain shared AsyncHTTPClient client with `send` and `data()` for outgoing requests.

Multipart uploads use `multipart-kit`, pinned to exactly `5.0.0-beta.2`; see [Routes](docs/routes.md#uploads).

## Schemas

```swift
/// A search in the product catalog.
@Schema
struct ProductQuery: Codable, Sendable {
    /// What to search for.
    @Length(min: 3, max: 200) var query: String
    @Range(1...20) var pageSize: Int = 10
    var categories: [Category] = []
}

ProductQuery.jsonSchema.json      // JSON Schema, keys in declaration order
ProductQuery.jsonSchema.strict()  // the strict form OpenAI's structured outputs and tools take
try query.validate()              // page_size: must be at most 20
```

`@Schema` derives a JSON Schema from a struct or an enum and generates the snake_case `Codable` that matches it:
doc comments become descriptions, a property's initial value is used when its key is missing, and enums can be
tagged or untagged unions. `@Length`, `@Range` and `@Pattern` add constraints that go into the schema and into
`validate()`. See [Schemas](docs/schemas.md).

## Routes

```swift
let orderRouter = APIRouter("/orders", tag: .orders)

/// Creates an order.
@POST(orderRouter, "/")
func createOrder(user: AuthUser, body: CreateOrderInput) async throws -> OrderResponse { ... }

@GET(orderRouter, "/:orderID")
func showOrder(user: AuthUser, orderID: Int64) async throws -> OrderResponse { ... }

let router = Router()
try OpenAPIDocument(title: "Shop API", version: "0.1.0", routers: [orderRouter]).register(on: router)
```

Handlers are top-level functions whose parameters bind by shape: a path segment, the JSON `body`, a multipart `form`,
the `query`, or a `RequestResolvable` such as the authenticated user. Nobody lists the handlers: each route macro
records itself in a section of the binary, found through dyld on macOS and through the ELF section on Linux.
`register(on:)` adds every route plus `/openapi.json` and Swagger UI at `/docs`. See [Routes](docs/routes.md).

## Environment configuration

```swift
@EnvConfig
struct Env {
    var databaseURL: String         // DATABASE_URL, required
    var appEnv: String = "local"    // APP_ENV, defaults to "local"
    var port: Int = 8000
    var paymentAPIKey: Secret?      // PAYMENT_API_KEY, optional
    var devMode: Bool = false       // true/false, yes/no, 1/0
    @Range(1...) var concurrency: Int = 4
    var allowedHosts: [String]      // ALLOWED_HOSTS=a.example, b.example
    var logFormat: LogFormat = .text
}

enum LogFormat: String, EnvValue { case text, json }

let env = Env.load()
```

- Names are SCREAMING_SNAKE_CASE of the property; an acronym run ends before a capitalized word
  (`databaseURL` → `DATABASE_URL`, `openaiAPIKey` → `OPENAI_API_KEY`, but `openAIAPIKey` → `OPEN_AIAPI_KEY`) and keeps
  a plural `s` (`allowedHostIDs` → `ALLOWED_HOST_IDS`).
- Process environment variables override the working directory's `.env`. Reading goes through `swift-configuration`.
- Missing required variables stop the process with one message listing all of them; invalid values name the key.
- Values are trimmed, and a variable that is empty after trimming counts as missing: a required one is reported, an
  optional one is `nil` or its default.
- Property types: `String`, `Int`, `Double`, `Bool`, `Secret`, `[String]`, `String` raw-value enums that conform to
  `EnvValue`, and their Optionals.
- `[String]` reads a comma-separated value; entries are trimmed and empty ones dropped. A required list without
  entries counts as missing.
- `@Range` on a numeric property stops `load()` when the value, or the default, is outside the range. An unknown enum
  value stops it too.

## HTTP client

`CoreKitHTTPClient` is a separate product, so `CoreKit` alone doesn't pull in AsyncHTTPClient.

```swift
import AsyncHTTPClient
import CoreKitHTTPClient

var request = HTTPClientRequest(url: "https://api.example.com/orders")
request.method = .POST
request.setBearerAuth(token)
try request.setJSONBody(order)
let response = try await HTTPClient.plain.send(request, timeout: .seconds(10))
let body = try await response.data()  // or response.text()
```

- `HTTPClient.plain` adds nothing of its own to a request: it has no timeout unless the request sets one, and a
  refused connection fails at once. It opens a connection for every request a host is sent at once, up to 1024.
  AsyncHTTPClient's `HTTPClient.shared` is set up like a browser: it retries a refused connection for 90 seconds, ends
  a request after 90 seconds without data, and queues requests beyond 8 connections to a host.
- `HTTPClient.plain(connectTimeout: .seconds(10))` makes a client like `plain` that gives up connecting after that
  time, with `HTTPClientError.connectTimeout`. Keep it in a `static let`: a client is never shut down.
- `send` returns the response once it has started. `timeout` limits the whole exchange, from connecting until the body
  has been read: `data()` and `text()` fail with `HTTPClientError.deadlineExceeded` when the body is not complete by
  then, and `HTTPClient.isTimeout(error)` recognizes that failure. AsyncHTTPClient's own deadline stops at the
  response's first byte.
- A header value with a control character, such as a line break, fails `send` with `InvalidHeaderValueError`, which
  names the header and leaves its value, perhaps a credential, out of the message.
- `request.setBearerAuth(token)` sets the `Authorization` header, and `try request.setJSONBody(value)` encodes
  `value` as the body and sets the `Content-Type`. Pass another encoder's method as `encode:` when the default
  `JSONEncoder` won't do: `encode: OrderedJSONEncoder().encode`.
- `request.addQuery([(name: "q", value: "New York")])` appends form-encoded fields to the URL's query: a space becomes
  `+`, and every byte other than an ASCII letter, a digit or one of `*-._` becomes `%XX`.
- `text()` reads the body as UTF-8 and turns invalid bytes into `�`.
- `HTTPClient.isConnectionFailure(error)` tells whether a failed request never reached the server (connection
  refused, name not resolved), which makes it safe to send again.

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

## Public initializers

```swift
@PublicInit
public struct Shipment: Sendable {
    public var orderID: String
    public var carrier: String?
    public var items: [String] = []
}

Shipment(orderID: "42", carrier: nil)
```

- Swift's own memberwise initializer is internal. `@PublicInit` generates the public one, with the stored properties
  in declaration order.
- A property's initial value is the parameter's default. A `let` with an initial value is left out.
- An Optional property is required unless it declares `= nil`, so a new field can't be forgotten at a call site.
- Structs only, and every stored property needs a type annotation.

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

## Ordered JSON

```swift
let data = try OrderedJSONEncoder().encode(order)
let pretty = try OrderedJSONEncoder(omitsNil: true, prettyPrinted: true, lowercaseUUIDs: true).encode(order)
let tree = try OrderedJSONEncoder().jsonValue(order)
let value = try JSONDecoder().decode(JSONValue.self, from: data)
let settings = try value.decode(Settings.self)
```

- `OrderedJSONEncoder` writes object keys in the order the type encodes them, which for synthesized `Codable` is
  declaration order. `JSONEncoder` doesn't keep it.
- A `nil` property is written as `null` unless `omitsNil` is set. `Date` is ISO-8601 or what a
  `dateEncoding: .custom { ... }` closure returns; `UUID` is uppercase, as with `JSONEncoder`, or lowercase. `URL` is
  its absolute string and `Data` is Base64.
- `/` and non-ASCII characters are written as they are. A `Double` always has a fraction (`47.0`), an `Int` never.
  A `Decimal` is a number as well (`12.34`, or `5` when whole), exact to the 17 digits a `Double` holds.
- An integer has to fit in `Int`: encoding a `UInt64` above `Int.max` throws.
- It is 1.3 to 3 times slower than `JSONEncoder`, more so with many short values or many escapes. Use it where key
  order or the exact bytes matter.
- `jsonValue(_:)` gives the encoded value as a `JSONValue` instead of bytes, with the same options.
- `value.decode(Settings.self)` goes the other way and reads a `JSONValue` as a `Decodable` type.
- `JSONValue` decodes any JSON document and keeps the key order of the objects it is built from;
  `serialized(pretty:)` writes it in that order. Decoded through `JSONDecoder`, objects lose the document's key order
  and a whole number becomes `.int` even when written `47.0`. As a `@Schema` property it is documented as any value.

## Logging

`CompactLogHandler` is a swift-log handler that writes one coloured line per message to standard output, in the
compact form of Rust's `tracing`: time, level, logger label, message, then the metadata as `key=value` sorted by key.

```swift
LoggingSystem.bootstrap { CompactLogHandler(label: $0, logLevel: .info) }
// 2026-01-02T03:04:05.678901Z  INFO order-api: Created order id=42 owner=alice
```

The colours are ANSI codes and are written whether or not the output is a terminal, so a log viewer that renders
them shows `ERROR` in red, `WARN` in yellow and `INFO` in green.

`withLogMetadata(["order_id": "42"]) { ... }` puts its metadata on every line logged inside the closure, by any
logger and by the tasks started in it, so code that knows nothing about the order still logs its id. Calls nest.

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
