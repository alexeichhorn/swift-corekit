import CoreKit
import Foundation
import Testing

@Schema
struct WeatherReport: Codable {
    /// City name.
    let city: String
    let observedAt: Date?
    let temperatureCelsius: Double
    let conditions: [Condition]
}

@Schema
enum Condition: String, Codable {
    case sunny, cloudy
}

@Schema(name: "Address")
struct ShippingAddressInput: Codable {
    let city: String
}

@Schema
struct Shipment: Codable {
    let from: ShippingAddressInput
    let to: ShippingAddressInput
}

@Test func schemaNameReplacesTheTypeName() {
    #expect(
        Shipment.jsonSchema.strict().serialized() == """
            {"$defs":{"Address":{"additionalProperties":false,"properties":{"city":{"title":"City","type":"string"}},\
            "required":["city"],"title":"Address","type":"object"}},"additionalProperties":false,"properties":{\
            "from":{"$ref":"#/$defs/Address"},"to":{"$ref":"#/$defs/Address"}},\
            "required":["from","to"],"title":"Shipment","type":"object"}
            """
    )
}

@Test func strictSchemaRequiresEveryPropertyAndForbidsExtras() {
    #expect(
        WeatherReport.jsonSchema.strict().serialized() == """
            {"additionalProperties":false,"properties":{\
            "city":{"description":"City name.","title":"City","type":"string"},\
            "observed_at":{"anyOf":[{"format":"date-time","type":"string"},{"type":"null"}],"title":"Observed At"},\
            "temperature_celsius":{"title":"Temperature Celsius","type":"number"},\
            "conditions":{"items":{"enum":["sunny","cloudy"],"type":"string"},"title":"Conditions","type":"array"}},\
            "required":["city","observed_at","temperature_celsius","conditions"],"title":"WeatherReport","type":"object"}
            """
    )
}

/// A shape to draw.
@Schema(tag: "kind")
enum Shape: Codable, Equatable {
    case circle(Circle)
    case roundedRect(RoundedRect)

    @Schema
    struct Circle: Codable, Equatable {
        let radius: Double
    }

    @Schema
    struct RoundedRect: Codable, Equatable {
        let width: Double
        let cornerRadius: Double?
    }
}

@Test func taggedEnumRoundTripsAndStaysStrict() throws {
    let shapes: [Shape] = [.circle(.init(radius: 1)), .roundedRect(.init(width: 2, cornerRadius: nil))]
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = String(decoding: try encoder.encode(shapes), as: UTF8.self)
    #expect(json == #"[{"kind":"circle","radius":1},{"kind":"rounded_rect","width":2}]"#)
    #expect(try JSONDecoder().decode([Shape].self, from: Data(json.utf8)) == shapes)
    #expect(shapes.map(\.kind) == ["circle", "rounded_rect"])
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Shape.self, from: Data(#"{"kind":"square"}"#.utf8)) }

    #expect(
        Shape.jsonSchema.strict().serialized() == """
            {"$defs":{"Shape.Circle":{"additionalProperties":false,"properties":{"radius":{"title":"Radius","type":"number"},\
            "kind":{"const":"circle","title":"Kind","type":"string"}},"required":["radius","kind"],"title":"Shape.Circle","type":"object"},\
            "Shape.RoundedRect":{"additionalProperties":false,"properties":{"width":{"title":"Width","type":"number"},\
            "corner_radius":{"anyOf":[{"type":"number"},{"type":"null"}],"title":"Corner Radius"},\
            "kind":{"const":"rounded_rect","title":"Kind","type":"string"}},"required":["width","corner_radius","kind"],\
            "title":"Shape.RoundedRect","type":"object"}},\
            "anyOf":[{"$ref":"#/$defs/Shape.Circle"},{"$ref":"#/$defs/Shape.RoundedRect"}],\
            "description":"A shape to draw.","title":"Shape"}
            """
    )
}

@Schema
struct HugeBounds: Codable {
    @Range(-1e20...1e20)
    let amount: Double
}

/// A definition whose name needs escaping inside a `$ref`.
struct SpacedMode: SchemaRepresentable {
    static var jsonSchema: JSONSchema { .enumeration(name: "Paint Mode", description: nil, values: ["matte", "glossy"]) }
}

struct Size: SchemaRepresentable {
    static var jsonSchema: JSONSchema {
        .object(name: "Größe", description: nil, properties: [.init("value", UInt8.self)])
    }
}

@Test func hugeBoundsStayExact() {
    let schema = HugeBounds.jsonSchema.strict().serialized()

    #expect(schema.contains(#""maximum":1e+20,"minimum":-1e+20"#))
}

@Test func percentEncodedDefinitionNamesResolve() {
    let schema = JSONSchema.object(
        name: "EncodedNames",
        description: nil,
        properties: [.init("mode", SpacedMode.self), .init("size", Size.self, description: "The size to use.")]
    ).strict().serialized()

    #expect(
        schema == """
            {"$defs":{"Größe":{"additionalProperties":false,\
            "properties":{"value":{"maximum":255,"minimum":0,"title":"Value","type":"integer"}},\
            "required":["value"],"title":"Größe","type":"object"}},\
            "additionalProperties":false,"properties":{\
            "mode":{"enum":["matte","glossy"],"title":"Mode","type":"string"},\
            "size":{"description":"The size to use.","additionalProperties":false,\
            "properties":{"value":{"maximum":255,"minimum":0,"title":"Value","type":"integer"}},\
            "required":["value"],"title":"Größe","type":"object"}},\
            "required":["mode","size"],"title":"EncodedNames","type":"object"}
            """
    )
}
