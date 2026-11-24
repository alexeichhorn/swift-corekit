/// Generates a `public init` with one parameter per stored property, in declaration order. Swift's own memberwise
/// initializer is internal, so a public struct that another module creates needs one written out.
///
/// A property's initial value becomes the parameter's default; a `let` with an initial value is left out. Unlike
/// Swift's own initializer, an Optional property is required unless it declares `= nil`. Write a closure property's
/// type out; behind a type alias it isn't recognized as escaping.
@attached(member, names: named(init))
public macro PublicInit() = #externalMacro(module: "CoreKitMacros", type: "PublicInitMacro")

/// Runs the body of an `async throws` function through `retry`, which retries it when it throws a retryable error.
///
/// Can't be combined with `@Timeout`, since Swift applies only one body macro per function; pass `timeout:` instead.
@attached(body)
public macro Retry(
    maxRetries: Int = 20,
    initialDelay: Duration = .seconds(1),
    exponentialBase: Int = 2,
    maxDelay: Duration = .seconds(180),
    jitter: Bool = true
) = #externalMacro(module: "CoreKitMacros", type: "RetryMacro")

/// `@Retry` with every attempt limited to `timeout`. The function's parameters and result must be `Sendable`, and so
/// must `self` in a method. The body runs in a child task, so in an actor it can't touch the actor's state directly.
@attached(body)
public macro Retry(
    maxRetries: Int = 20,
    initialDelay: Duration = .seconds(1),
    exponentialBase: Int = 2,
    maxDelay: Duration = .seconds(180),
    jitter: Bool = true,
    timeout: Duration
) = #externalMacro(module: "CoreKitMacros", type: "RetryMacro")

/// Runs the body of an `async throws` function through `withTimeout`, which throws `TimeoutError` when it takes
/// longer. The function's parameters and result must be `Sendable`, and so must `self` in a method. The body runs in a
/// child task, so in an actor it can't touch the actor's state directly.
@attached(body)
public macro Timeout(_ timeout: Duration) = #externalMacro(module: "CoreKitMacros", type: "TimeoutMacro")
