/// Derives a JSON Schema from a struct or an enum and conforms it to `SchemaRepresentable`.
///
/// For structs it also generates `CodingKeys` that map every stored property to its snake_case JSON key
/// (`dueAt` → `due_at`), so `Codable` and the schema always agree. Doc comments become `description`s. A `var` with an
/// initial value keeps that value when the JSON has no key for it.
///
/// Enums either have `String`/`Int` raw values, or are unions whose cases each wrap one unlabeled value
/// (`case text(String)`). A union is encoded as the wrapped value; the generated `Codable` decodes the first case,
/// in declaration order, whose value fits.
@attached(member, names: named(CodingKeys), named(init(from:)), named(encode(to:)))
@attached(extension, conformances: SchemaRepresentable, names: named(jsonSchema), named(validate(_:at:into:)), named(init(from:)))
public macro Schema() = #externalMacro(module: "CoreKitMacros", type: "SchemaMacro")

/// `@Schema` for a struct, with the schema named `name` instead of after the type: a reader of the schema, such as a
/// model, sees `Address` where the code says `ShippingAddressInput`.
///
/// ```swift
/// @Schema(name: "Address")
/// struct ShippingAddressInput: Codable { … }
/// ```
@attached(member, names: named(CodingKeys), named(init(from:)), named(encode(to:)))
@attached(extension, conformances: SchemaRepresentable, names: named(jsonSchema), named(validate(_:at:into:)), named(init(from:)))
public macro Schema(name: String) = #externalMacro(module: "CoreKitMacros", type: "SchemaMacro")

/// A tagged union: every case wraps one `@Schema` struct, encoded as that struct's object plus `tag` set to the
/// snake_case case name (`case linkList(LinkList)` → `"kind": "link_list"`), or to the case's `@Tag`.
///
/// Generates `Codable` and a `String` property named `tag` that returns the case's tag value. The payload structs
/// must not have a property encoded under the `tag` key.
///
/// Decoding fails for a tag that no case has, unless one case is marked `@UnknownTag`.
@attached(member, names: named(CodingKeys), named(init(from:)), named(encode(to:)), arbitrary)
@attached(extension, conformances: SchemaRepresentable, names: named(jsonSchema), named(validate(_:at:into:)), named(init(from:)))
public macro Schema(tag: String) = #externalMacro(module: "CoreKitMacros", type: "SchemaMacro")

/// Gives a case of a `@Schema(tag:)` enum a tag value other than its snake_case name:
/// `@Tag("order.created") case orderCreated(OrderCreated)`.
@attached(peer)
public macro Tag(_ value: String) = #externalMacro(module: "CoreKitMacros", type: "UnionCaseMacro")

/// Marks the case of a `@Schema(tag:)` enum that every tag without a case of its own decodes to, for a union of which
/// only some variants are read. The case has no associated value.
///
/// Such an enum can only be `Decodable`, and it gets no tag property, since that case has no tag value.
@attached(peer)
public macro UnknownTag() = #externalMacro(module: "CoreKitMacros", type: "UnionCaseMacro")

/// Generates a `public init` with one parameter per stored property, in declaration order. Swift's own memberwise
/// initializer is internal, so a public struct that another module creates needs one written out.
///
/// A property's initial value becomes the parameter's default; a `let` with an initial value is left out. Unlike
/// Swift's own initializer, an Optional property is required unless it declares `= nil`. Write a closure property's
/// type out; behind a type alias it isn't recognized as escaping.
@attached(member, names: named(init))
public macro PublicInit() = #externalMacro(module: "CoreKitMacros", type: "PublicInitMacro")

/// Limits the length of a `String` property, counted in Unicode scalars, or the number of items of an array property.
///
/// A marker for `@Schema`, which adds `minLength`/`maxLength` or `minItems`/`maxItems` to the schema and checks them
/// in `validate()`. On an Optional property it applies when a value is present.
@attached(peer)
public macro Length(min: Int? = nil, max: Int? = nil) = #externalMacro(module: "CoreKitMacros", type: "ConstraintMacro")

/// Limits a numeric property to inclusive bounds: `@Range(1...20)`, `@Range(1...)` or `@Range(...20)`. On an array of
/// numbers it limits every item. A bound of an integer property may be at most 2^53 - 1 in size, the largest a
/// `Double` compares exactly.
///
/// A marker for `@Schema`, which adds `minimum`/`maximum` to the schema and checks them in `validate()`, and for
/// `@EnvConfig`, whose `load()` stops when the value is out of range.
@attached(peer)
public macro Range<Bounds: RangeExpression>(_ bounds: Bounds) = #externalMacro(module: "CoreKitMacros", type: "ConstraintMacro")

/// Requires a `String` property to match a regular expression; anchor it with `^` and `$` to match the whole string.
/// On an array of strings every item has to match.
///
/// A marker for `@Schema`, which adds `pattern` to the schema and checks it in `validate()`.
@attached(peer)
public macro Pattern(_ regex: String) = #externalMacro(module: "CoreKitMacros", type: "ConstraintMacro")

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
