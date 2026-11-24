import CoreKit
import Foundation
import Testing

// The pydantic counterparts of these types are in `scripts/strict-schema-fixtures.py`, which writes what OpenAI's
// Python SDK makes of them to `Tests/StrictSchemaFixtures`.

@Schema
enum ParityStatus: String, Codable {
    case open, shipped
}

@Schema
struct ParityCustomer: Codable {
    let name: String
    let email: String?
}

/// Where an order goes.
@Schema
struct ParityAddress: Codable {
    let city: String
    let zip: String
}

/// An order as a model reads it.
///
/// Placed by a customer.
@Schema
struct ParityOrder: Codable {
    /// Shown on the receipt.
    let note: String
    let id: UUID
    let placedAt: Date?
    let total: Double
    let homepage: URL
    let isGift: Bool
    let quantity: UInt8
    let status: ParityStatus
    var tags: [String] = []
    var priority: Int = 3
    var weight: Double = 1
    var label: String? = "draft"
    var fallbackStatus: ParityStatus = .open
    let extra: JSONValue
    let customer: ParityCustomer
    /// The address to ship to.
    let shipTo: ParityAddress
    let billTo: ParityAddress?
}

@Schema
struct ParityCard: Codable {
    let title: String
}

@Schema
enum ParityContent: Codable {
    case text(String)
    case lines([String])
    case card(ParityCard)
}

/// Paid by card.
@Schema
struct ParityCardPayment: Codable {
    let last4: String
}

@Schema
struct ParityGiftCard: Codable {
    let code: String
    var amount: Int = 50
}

/// How the order is paid.
@Schema(tag: "kind")
enum ParityPayment: Codable {
    case card(ParityCardPayment)
    @Tag("gift-card") case giftCard(ParityGiftCard)
}

@Schema
struct ParitySearch: Codable {
    @Length(min: 3, max: 200) var query: String
    @Range(1...20) var pageSize: Int
    @Range(0.5...) var minRating: Double
    @Pattern("^[a-z]{2}$") var region: String?
    @Length(max: 5) @Pattern("^[a-z]+$") var tags: [String]?
    @Range(1...5) var ratings: [Int]
    @Length(min: 1) var codes: [String]
    @Range(1...10) var rank: UInt8
    let content: ParityContent
    let payment: ParityPayment?
}

/// `strict()` writes exactly what OpenAI's Python SDK writes for the pydantic counterpart, byte for byte.
@Test(arguments: [
    ("ParityOrder", ParityOrder.jsonSchema),
    ("ParitySearch", ParitySearch.jsonSchema),
    ("ParityPayment", ParityPayment.jsonSchema),
])
func strictSchemaMatchesOpenAIsSDK(name: String, schema: JSONSchema) throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "StrictSchemaFixtures/\(name).json")
    let expected = try String(contentsOf: fixture, encoding: .utf8).trimmingCharacters(in: .newlines)

    #expect(schema.strict().serialized() == expected)
}

@Schema
struct ParityRefund: Codable {
    let amount: Int
}

@Schema(tag: "type")
enum ParityEvent: Codable {
    case refund(ParityRefund)
}

@Schema
struct ParityLedger: Codable {
    let event: ParityEvent
    let lastRefund: ParityRefund
}

/// A tagged variant is defined with its tag, so its struct can't also appear on its own in the same schema.
@Test func aPayloadUsedOnItsOwnAndAsATaggedVariantStops() async {
    await #expect(processExitsWith: .failure) { _ = ParityLedger.jsonSchema.strict() }
}
