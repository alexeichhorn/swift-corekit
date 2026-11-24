import CoreKit
import Foundation
import Testing

@Test func untypedJSONAllowsAnyValueInASchema() {
    #expect([JSONValue].jsonSchema.json.serialized() == #"{"type":"array","items":{}}"#)
}

@Schema
struct Catalog: Codable {
    let id: UUID
    let homepage: URL
    let updatedAt: Date
    let isPublic: Bool
    let stock: [String: Int32]
    let ratio: Float
    let metadata: JSONValue
}

@Test func schemaCoversTheSupportedTypes() {
    #expect(
        Catalog.jsonSchema.json.serialized() == """
            {"type":"object","properties":{"id":{"type":"string","format":"uuid"},\
            "homepage":{"type":"string","format":"uri"},"updated_at":{"type":"string","format":"date-time"},\
            "is_public":{"type":"boolean"},"stock":{"type":"object","additionalProperties":{"type":"integer","format":"int32"}},\
            "ratio":{"type":"number","format":"float"},"metadata":{}},\
            "required":["id","homepage","updated_at","is_public","stock","ratio","metadata"]}
            """
    )
}

@Schema
struct Listing: Codable {
    let id: UUID
    let homepage: URL
    @Range(1...5) var rating: UInt8
    let views: UInt16
}

/// OpenAI rejects the `uri` format, and a sized integer gets the bounds of its type unless `@Range` sets them.
@Test func strictSchemaLeavesOutRejectedFormatsAndBoundsSizedIntegers() {
    #expect(
        Listing.jsonSchema.strict().serialized() == """
            {"additionalProperties":false,"properties":{"id":{"format":"uuid","title":"Id","type":"string"},\
            "homepage":{"title":"Homepage","type":"string"},\
            "rating":{"maximum":5,"minimum":1,"title":"Rating","type":"integer"},\
            "views":{"maximum":65535,"minimum":0,"title":"Views","type":"integer"}},\
            "required":["id","homepage","rating","views"],"title":"Listing","type":"object"}
            """
    )
}

enum Storefront {
    @Schema
    struct Item: Codable {
        let name: String
    }
}

@Schema
struct Basket: Codable {
    let items: [Storefront.Item]
}

/// A nested type is named after its nesting path; a top-level one keeps its plain name.
@Test func schemasAreNamedAfterTheNestingPath() {
    let strict = Basket.jsonSchema.strict().serialized()
    #expect(strict.contains(##""$defs":{"Storefront.Item":{"##))
    #expect(strict.contains(##""items":{"$ref":"#/$defs/Storefront.Item"}"##))
    #expect(strict.contains(#""title":"Basket""#))
}

@Schema
enum Note: Codable, Equatable {
    case count(Int)
    case text(String)
    case lines([String])
}

@Test func untaggedUnionDecodesTheFirstCaseThatFits() throws {
    let json = #"[3,"three",["a","b"]]"#
    let notes = try JSONDecoder().decode([Note].self, from: Data(json.utf8))

    #expect(notes == [.count(3), .text("three"), .lines(["a", "b"])])
    #expect(String(decoding: try JSONEncoder().encode(notes), as: UTF8.self) == json)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Note.self, from: Data("true".utf8)) }
}

@Schema
struct Invoice: Codable {
    let currency: String = "EUR"
    var total: Int = 0
}

@Test func aLetWithAnInitialValueIsNeverDecoded() throws {
    let invoice = try JSONDecoder().decode(Invoice.self, from: Data(#"{"currency":"USD","total":5}"#.utf8))
    #expect(invoice.currency == "EUR")
    #expect(invoice.total == 5)
}

@Schema
struct Coupon: Codable {
    var code: String = "NONE"

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code).uppercased()
    }
}

@Test func aStructsOwnDecodingInitializerIsKept() throws {
    #expect(try JSONDecoder().decode(Coupon.self, from: Data(#"{"code":"spring"}"#.utf8)).code == "SPRING")
}

@Schema
struct PageRequest: Codable {
    @Range(1...20) var pageSize: Int
    @Length(max: 2) var tags: [String]
}

@Test func validationErrorDescribesEveryIssue() {
    let error = #expect(throws: ValidationError.self) { try PageRequest(pageSize: 21, tags: ["a", "b", "c"]).validate() }
    #expect(error?.description == "page_size: must be at most 20; tags: must have at most 2 items")
}
