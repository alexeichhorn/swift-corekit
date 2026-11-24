import CoreKit
import Foundation
import Testing

private struct ToolResult: Encodable {
    var url = "https://example.com/a/b"
    var city = "Zürich 東京"
    var note: String?
    var score = 47.0
    var count = 47
    var ratio: Float = 0.1
    var id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    var createdAt = Date(timeIntervalSince1970: 1_767_323_045)
    var link = URL(string: "https://example.com/articles?page=2")!
    var pages = [Page()]

    struct Page: Encodable {
        var title = "Articles"
        var cursor: Int?
    }
}

@Test func orderedEncoderWritesKeysInDeclarationOrder() throws {
    let compact = String(decoding: try OrderedJSONEncoder().encode(ToolResult()), as: UTF8.self)
    #expect(
        compact == """
            {"url":"https://example.com/a/b","city":"Zürich 東京","note":null,"score":47.0,"count":47,"ratio":0.1,\
            "id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","createdAt":"2026-01-02T03:04:05Z",\
            "link":"https://example.com/articles?page=2","pages":[{"title":"Articles","cursor":null}]}
            """
    )

    let encoder = OrderedJSONEncoder(
        omitsNil: true,
        prettyPrinted: true,
        dateEncoding: .custom { .int(Int($0.timeIntervalSince1970)) },
        lowercaseUUIDs: true
    )
    #expect(
        String(decoding: try encoder.encode(ToolResult()), as: UTF8.self) == """
            {
              "url": "https://example.com/a/b",
              "city": "Zürich 東京",
              "score": 47.0,
              "count": 47,
              "ratio": 0.1,
              "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
              "createdAt": 1767323045,
              "link": "https://example.com/articles?page=2",
              "pages": [
                {
                  "title": "Articles"
                }
              ]
            }
            """
    )

    #expect(throws: EncodingError.self) { try OrderedJSONEncoder().encode([Double.nan]) }
    #expect(String(decoding: try OrderedJSONEncoder().encode(Reopened()), as: UTF8.self) == #"{"child":{"first":1,"second":2}}"#)
}

/// Asks for the same nested container twice, as hand-written `encode(to:)` methods sometimes do.
private struct Reopened: Encodable {
    enum CodingKeys: CodingKey { case child, first, second }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var first = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .child)
        try first.encode(1, forKey: .first)
        var second = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .child)
        try second.encode(2, forKey: .second)
    }
}

@Test func jsonValueDecodesAnyDocument() throws {
    let document = #"[null,true,3,-2.5,"x",{"a":[1,{"b":"c"}]},[],{}]"#
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(document.utf8))
    #expect(value.serialized() == document)
    #expect(String(decoding: try OrderedJSONEncoder().encode(value), as: UTF8.self) == document)
}

@Test func orderedEncoderWritesADecimalAsANumber() throws {
    struct Price: Encodable {
        let amount: Decimal
        let quantity: Decimal
    }
    let price = Price(amount: Decimal(string: "12.34")!, quantity: 5)
    #expect(String(decoding: try OrderedJSONEncoder().encode(price), as: UTF8.self) == #"{"amount":12.34,"quantity":5}"#)
}

@Test func orderedEncoderEscapesControlCharactersLikeSerde() throws {
    let text = "a\u{8}b\u{c}c\u{1f}d\n\"e\"/\u{7f}"
    let encoded = String(decoding: try OrderedJSONEncoder().encode(text), as: UTF8.self)
    #expect(encoded == #""a\bb\fc\u001fd\n\"e\"/\#u{7f}""#)
}

@Test func jsonValueDecodesAsATypedValue() throws {
    struct Point: Decodable, Equatable {
        var x: Double
        var label: String?
    }
    let value: JSONValue = ["points": [["x": 47, "label": "Zürich \"HB\""], ["x": 8.5, "label": nil]]]

    #expect(try value.decode([String: [Point]].self) == ["points": [Point(x: 47, label: "Zürich \"HB\""), Point(x: 8.5, label: nil)]])
    #expect(throws: DecodingError.self) { try value.decode(Point.self) }
}

/// An integer that doesn't fit in `Int` has no exact JSON number here, so encoding it throws.
@Test func orderedEncoderRefusesIntegersBeyondInt() throws {
    #expect(String(decoding: try OrderedJSONEncoder().encode([UInt64(Int.max)]), as: UTF8.self) == "[9223372036854775807]")
    #expect(throws: EncodingError.self) { try OrderedJSONEncoder().encode([UInt64(Int.max) + 1]) }
}

@Test func orderedEncoderGivesAJSONValueWithTheSameOptions() throws {
    struct Attachment: Encodable {
        var name = "receipt.txt"
        var note: String?
        var bytes = Data("hi".utf8)
    }
    let value = try OrderedJSONEncoder(omitsNil: true).jsonValue(Attachment())
    #expect(value.serialized() == #"{"name":"receipt.txt","bytes":"aGk="}"#)
}

@Test func jsonValueDecodesWholeNumbersAsIntegers() throws {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data("[47.0,47.5,-3]".utf8))
    #expect(value.serialized() == "[47,47.5,-3]")
}

@Test func orderedEncoderWritesLongStringsThatMixPlainTextAndEscapes() throws {
    let segment = "order 47: \"Zürich 東京\"\n\tpaid\\ 👍🏽 e\u{301}\u{1}/"
    let escaped = #"order 47: \"Zürich 東京\"\n\tpaid\\ 👍🏽 e\#u{301}\u0001/"#
    let encoded = String(decoding: try OrderedJSONEncoder().encode(String(repeating: segment, count: 200)), as: UTF8.self)
    #expect(encoded == "\"" + String(repeating: escaped, count: 200) + "\"")
}

@Test func orderedEncoderEscapesAtTheStartAndEnd() throws {
    let cases = [
        ("", #""""#),
        ("\"", #""\"""#),
        ("\n", #""\n""#),
        ("\\\\", #""\\\\""#),
        ("\"order\"", #""\"order\"""#),
        ("\u{0}order\u{1f}", #""\u0000order\u001f""#),
        ("\n東京", #""\n東京""#),
        ("東京\t", #""東京\t""#),
        // A combining mark joins the quote into one character, yet only the quote is escaped.
        ("\"\u{301}", #""\"\#u{301}""#),
    ]
    for (text, expected) in cases {
        #expect(String(decoding: try OrderedJSONEncoder().encode(text), as: UTF8.self) == expected)
    }
}
