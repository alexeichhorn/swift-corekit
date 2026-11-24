# Schemas

`@Schema` derives a JSON Schema from a Swift type, generates the `Codable` that matches it, and checks the type's
constraints in `validate()`.

```swift
import CoreKit

/// Input for creating an order.
@Schema
struct CreateOrderInput: Codable, Sendable {
    /// Shown on the receipt.
    let note: String
    let deliverAt: Date?
}

@Schema
enum OrderStatus: String, Codable, Sendable { case open, shipped }

/// Wire format: `{"kind": "gift_card", "amount": 50}`.
@Schema(tag: "kind")
enum Payment: Codable, Sendable {
    case card(CardPayment)        // a @Schema struct
    case giftCard(GiftCardPayment)
}

/// Wire format: the wrapped value, `"some text"` or `[...]`.
@Schema
enum Content: Codable, Sendable {
    case text(String)
    case items([Item])
}

CreateOrderInput.jsonSchema           // JSONSchema
CreateOrderInput.jsonSchema.json      // JSON Schema with nested types inlined
CreateOrderInput.jsonSchema.strict()  // OpenAI structured-output / strict tool form, as OpenAI's Python SDK writes it
```

## Types

- Supported: `String`, `Bool`, all integer types, `Double`, `Float`, `Date` (`date-time`), `UUID`, `URL`, `Optional`,
  arrays, `[String: T]`, `JSONValue` (any value), other `@Schema` types, `String`/`Int` raw-value enums, and union
  enums.
- Schemas are named after the type's nesting path (`Storefront.Item`), so nested types may share a name. Top-level
  types keep their plain name. `@Schema(name: "Address")` on a struct names its schema explicitly, for a type whose
  name the schema's reader should not see.
- Doc comments become `description`s. Optional properties are not required and nullable.
- Self-referencing types (`let replies: [Comment]`) are not supported.

## Unions

Union enums wrap exactly one unlabeled value per case; `@Schema` generates their `Codable` and an `anyOf` schema.

- Tagged (`tag:`): every case wraps a `@Schema` struct, encoded as that struct's object plus the tag key set to the
  snake_case case name (`giftCard` → `gift_card`), or to the case's `@Tag("gift-card")`. The generated
  `var kind: String` (named after the tag) returns it; an unknown tag fails decoding. The payload structs must not
  have a property with the tag's key.
- To read only some variants of a tagged union, mark one case without a value `@UnknownTag`: every other tag decodes
  to it. Such an enum can only be `Decodable` and has no tag property.

  ```swift
  @Schema(tag: "type")
  enum ShopEvent: Decodable {
      @Tag("order.created") case orderCreated(Order)
      case refund(Order)
      @UnknownTag case other
  }
  ```
- Untagged: encoded as the wrapped value; decoding takes the first case, in declaration order, whose value decodes,
  so put the more specific cases first.

## Coding

- The wire format is snake_case: on structs `@Schema` generates `CodingKeys` (`deliverAt` → `deliver_at`,
  `userIDs` → `user_ids`), so `Codable` and the schema always agree with any encoder. Don't set a key encoding or
  decoding strategy, and don't declare `CodingKeys` yourself.
- A `var` with an initial value (`var tags: [String] = []`) keeps that value when the JSON has no key for it, and is
  not required in the schema. Only a missing key does that: `null` is `nil` for an optional property and an error for
  any other, and a value of the wrong type is an error. For this `@Schema` writes the struct's `init(from:)`, unless
  the struct has its own; there an optional behind a type alias counts as required. A `let` with an initial value is
  never decoded. Your own `init(from:)` has to be in the struct's body: the macro cannot see one in an extension, and
  the two would collide.
- Every stored property needs its type written out.

## Strict schemas

`strict()` writes what OpenAI's Python SDK writes for the same pydantic model, key for key: every property is
required, objects set `additionalProperties: false`, an optional value is an `anyOf` with `null`, every property has a
`title`, and a nested type is defined once under `$defs`. Keys are sorted, except the properties, which keep their
declaration order.

- A property's initial value (`var pageSize: UInt8 = 8`) is its `default`. The model still has to send the property;
  the default tells it which value to pick.
- A sized integer gets the bounds of its type (`UInt8` is 0 to 255) unless `@Range` sets them.
- Formats OpenAI rejects, such as `uri`, are left out. `[String: T]` can't be expressed in strict mode; unions can, as
  long as they aren't the root.
- Schemas render to `JSONValue`, which keeps key order (OpenAI generates in schema order). Send it with
  `serialized()`; its `Encodable` conformance goes through `JSONEncoder`, which reorders keys.

## Constraints

```swift
@Schema
struct ProductQuery: Codable, Sendable {
    @Length(min: 3, max: 200) var query: String    // Unicode scalars
    @Range(1...20) var pageSize: Int               // also 1... and ...20
    @Pattern("^[a-z]{2}$") var region: String?     // checked when present
    @Length(max: 5) var tags: [String]             // number of items
    @Pattern("^[A-Z]{2}$") var regions: [String]   // every item; so does @Range on an array of numbers
}

do {
    try query.validate()
} catch {
    error.issues  // [ValidationIssue]: path ([.key("page_size")]) and rule (.maximum(20))
    print(error)  // page_size: must be at most 20; tags: must have at most 5 items
}
```

- The constraints go into the schema as `minLength`/`maxLength`, `minItems`/`maxItems`, `minimum`/`maximum` and
  `pattern`; on an Optional property they sit on the non-null branch of an `anyOf`, and `@Pattern` and `@Range` on an
  array sit on its `items`. The length of an array's items can't be limited: `@Length` on an array counts the items.
- `validate()` reports every violation at once and also validates nested `@Schema` values, array elements and union
  payloads. Paths use the JSON keys, and array indices as `.index`.
- `@Pattern` matches anywhere in the string, by code point, with `\d` and `\w` covering ASCII only and `\s` any
  Unicode whitespace, as OpenAI reads a schema's `pattern`; anchor it with `^` and `$`.
- `@Range` compares numbers as `Double`s. A bound of an integer property may therefore be at most 2^53 - 1 in size;
  within that the check is exact for every integer, and a larger bound is a compile error.
- A constraint on a property type it doesn't apply to, or with a malformed argument, is a compile error. The type has
  to be written out; a type alias for `String` isn't recognized.
