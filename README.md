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

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE) at your option.
