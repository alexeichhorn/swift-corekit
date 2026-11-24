import CoreKit
import Foundation
import Testing

/// A webhook event, of which only the order events are read.
@Schema(tag: "type")
enum ShopEvent: Decodable, Equatable {
    @Tag("order.created") case orderCreated(Order)
    case refund(Order)
    @UnknownTag case other

    @Schema
    struct Order: Decodable, Equatable {
        let orderID: String
    }
}

@Test func taggedEnumDecodesCustomAndUnknownTags() throws {
    let json = """
        [{"type": "order.created", "order_id": "a"}, {"type": "refund", "order_id": "b"}, {"type": "stock.low", "item": "c"}]
        """
    let events = try JSONDecoder().decode([ShopEvent].self, from: Data(json.utf8))

    #expect(events == [.orderCreated(.init(orderID: "a")), .refund(.init(orderID: "b")), .other])
}

@Test func orderedEncoderWritesATaggedUnionAsOneObject() throws {
    // A tagged union writes its tag and then its payload into one object.
    let shapes: [Shape] = [.roundedRect(.init(width: 2, cornerRadius: nil))]
    #expect(
        String(decoding: try OrderedJSONEncoder().encode(shapes), as: UTF8.self)
            == #"[{"kind":"rounded_rect","width":2.0,"corner_radius":null}]"#)
}
