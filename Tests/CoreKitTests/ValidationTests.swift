import CoreKit
import Foundation
import Testing

@Schema
struct ProductQuery: Codable, Sendable {
    /// What to search for.
    @Length(min: 3, max: 200) var query: String
    @Range(1...20) var pageSize: Int
    @Pattern("^[a-z]{2}$") var region: String?
    @Length(max: 2) @Pattern("^[a-z]+$") var tags: [String]?
    var filters: [Filter] = []
    var price: Price?

    @Schema
    struct Filter: Codable, Sendable {
        @Length(min: 1) var path: String
        @Range(0...) var weight: Double = 1
    }

    @Schema
    enum Price: Codable, Sendable {
        case exact(Int)
        case band(Band)
    }

    @Schema
    struct Band: Codable, Sendable {
        @Range(...1_000_000) var upper: Int
    }
}

@Schema
struct Initial: Codable, Sendable {
    @Pattern("^.$") var letter: String
}

/// The schema counts code points, so validation must too: a letter with a combining accent is two.
@Test func patternsMatchByCodePointLikeTheSchema() throws {
    try Initial(letter: "\u{e9}").validate()
    #expect(throws: ValidationError.self) { try Initial(letter: "e\u{301}").validate() }
}

@Schema
struct Digit: Codable, Sendable {
    @Pattern(#"^\d\s$"#) var value: String
}

/// As OpenAI reads a pattern: `\d` is an ASCII digit, so an Arabic digit does not match, and `\s` is any Unicode
/// whitespace, so a no-break space does.
@Test func patternDigitsAreASCIIAndWhitespaceIsUnicode() throws {
    try Digit(value: "1 ").validate()
    try Digit(value: "1\u{A0}").validate()
    #expect(throws: ValidationError.self) { try Digit(value: "\u{661} ").validate() }
    #expect(throws: ValidationError.self) { try Digit(value: "1\u{FEFF}").validate() }
}

@Schema
struct Share: Codable, Sendable {
    @Range(0...0.1) var ratio: Float
}

/// A `Float` on its bound is within the range, although widened to a `Double` it is slightly above it.
@Test func floatRangesIncludeTheirBounds() throws {
    try Share(ratio: 0.1).validate()
    #expect(throws: ValidationError.self) { try Share(ratio: 0.2).validate() }
}

@Test func validateCollectsEveryViolatedRuleWithItsPath() throws {
    let valid = ProductQuery(query: "swift", pageSize: 20, region: "ch", tags: ["remote"])
    try valid.validate()
    try ProductQuery(query: "żółć", pageSize: 1, filters: [.init(path: "x", weight: 0)], price: .exact(5)).validate()

    let invalid = ProductQuery(
        query: "ab",
        pageSize: 21,
        region: "CH",
        tags: ["a", "B", "c"],
        filters: [.init(path: "title"), .init(path: "", weight: -0.5)],
        price: .band(.init(upper: 2_000_000))
    )
    let error = #expect(throws: ValidationError.self) { try invalid.validate() }
    #expect(
        error?.issues == [
            ValidationIssue(path: [.key("query")], rule: .minLength(3)),
            ValidationIssue(path: [.key("page_size")], rule: .maximum(20)),
            ValidationIssue(path: [.key("region")], rule: .pattern("^[a-z]{2}$")),
            ValidationIssue(path: [.key("tags")], rule: .maxItems(2)),
            ValidationIssue(path: [.key("tags"), .index(1)], rule: .pattern("^[a-z]+$")),
            ValidationIssue(path: [.key("filters"), .index(1), .key("path")], rule: .minLength(1)),
            ValidationIssue(path: [.key("filters"), .index(1), .key("weight")], rule: .minimum(0)),
            ValidationIssue(path: [.key("price"), .key("upper")], rule: .maximum(1_000_000)),
        ])
    #expect(error?.issues.first?.description == "query: must have at least 3 characters")
    #expect(error?.issues[6].description == "filters.1.weight: must be at least 0")
}

@Test func aMissingKeyLeavesTheInitialValue() throws {
    func decode(_ json: String) throws -> ProductQuery {
        try JSONDecoder().decode(ProductQuery.self, from: Data(json.utf8))
    }

    let query = try decode(#"{"query":"lamp","page_size":5,"filters":[{"path":"color"},{"path":"size","weight":2}]}"#)
    #expect(query.filters.map(\.weight) == [1, 2])
    #expect(try decode(#"{"query":"lamp","page_size":5}"#).filters.isEmpty)
    // `null` is not a missing key.
    #expect(throws: DecodingError.self) { try decode(#"{"query":"lamp","page_size":5,"filters":null}"#) }
    #expect(throws: DecodingError.self) { try decode(#"{"query":"lamp"}"#) }

    func label(_ json: String) throws -> String? {
        try JSONDecoder().decode(Labelled.self, from: Data(json.utf8)).label
    }
    #expect(try label("{}") == "draft")
    #expect(try label(#"{"label":null}"#) == nil)
    #expect(try label(#"{"label":"final"}"#) == "final")
    #expect(throws: DecodingError.self) { try label(#"{"label":1}"#) }
}

@Schema
private struct Labelled: Codable {
    var label: String? = "draft"
    // Every spelling of an optional may be left out.
    var note: Swift.Optional<String>
    var tag: Optional<String>
}

@Test func constraintsBecomeSchemaKeywords() {
    #expect(
        ProductQuery.jsonSchema.json.serialized() == """
            {"type":"object","properties":{\
            "query":{"type":"string","minLength":3,"maxLength":200,"description":"What to search for."},\
            "page_size":{"type":"integer","format":"int64","minimum":1,"maximum":20},\
            "region":{"anyOf":[{"type":"string","pattern":"^[a-z]{2}$"},{"type":"null"}]},\
            "tags":{"anyOf":[{"type":"array","items":{"type":"string","pattern":"^[a-z]+$"},"maxItems":2},{"type":"null"}]},\
            "filters":{"type":"array","items":{"type":"object","properties":{\
            "path":{"type":"string","minLength":1},"weight":{"type":"number","format":"double","minimum":0}},\
            "required":["path"]}},\
            "price":{"anyOf":[{"anyOf":[{"type":"integer","format":"int64"},{"type":"object","properties":{\
            "upper":{"type":"integer","format":"int64","maximum":1000000}},"required":["upper"]}]},{"type":"null"}]}},\
            "required":["query","page_size"]}
            """
    )
    let strict = ProductQuery.jsonSchema.strict().serialized()
    #expect(
        strict.contains(#""query":{"description":"What to search for.","maxLength":200,"minLength":3,"title":"Query","type":"string"}"#))
    #expect(strict.contains(#""page_size":{"maximum":20,"minimum":1,"title":"Page Size","type":"integer"}"#))
    #expect(strict.contains(#""region":{"anyOf":[{"pattern":"^[a-z]{2}$","type":"string"},{"type":"null"}],"title":"Region"}"#))
    #expect(strict.contains(#"{"items":{"pattern":"^[a-z]+$","type":"string"},"maxItems":2,"type":"array"}"#))
    // An initial value is the default the model is told.
    #expect(strict.contains(#""filters":{"default":[],"#))
    #expect(strict.contains(#""weight":{"default":1.0,"minimum":0,"title":"Weight","type":"number"}"#))
}
