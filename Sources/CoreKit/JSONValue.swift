import Foundation

/// A JSON document whose objects keep their key order.
///
/// Key order matters for schemas: Swagger UI lists properties in schema order, and OpenAI generates
/// structured output in schema order. `JSONEncoder` reorders keys, so use ``serialized(pretty:)``
/// whenever order matters; the `Encodable` conformance is for embedding into `Codable` payloads.
public enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    public func serialized(pretty: Bool = false) -> String {
        var output = ""
        write(to: &output, pretty: pretty, indent: 0)
        return output
    }

    private func write(to output: inout String, pretty: Bool, indent: Int) {
        switch self {
        case .null: output += "null"
        case .bool(let value): output += value ? "true" : "false"
        case .int(let value): output += String(value)
        case .double(let value): output += String(value)
        case .string(let value): Self.writeString(value, to: &output)
        case .array(let items):
            writeContainer(items, open: "[", close: "]", to: &output, pretty: pretty, indent: indent) { item, output in
                item.write(to: &output, pretty: pretty, indent: indent + 1)
            }
        case .object(let members):
            writeContainer(members, open: "{", close: "}", to: &output, pretty: pretty, indent: indent) { member, output in
                Self.writeString(member.key, to: &output)
                output += pretty ? ": " : ":"
                member.value.write(to: &output, pretty: pretty, indent: indent + 1)
            }
        }
    }

    private func writeContainer<Element>(
        _ elements: [Element],
        open: String,
        close: String,
        to output: inout String,
        pretty: Bool,
        indent: Int,
        writeElement: (Element, inout String) -> Void
    ) {
        output += open
        for (index, element) in elements.enumerated() {
            if index > 0 { output += "," }
            if pretty { output += "\n" + String(repeating: "  ", count: indent + 1) }
            writeElement(element, &output)
        }
        if pretty && !elements.isEmpty { output += "\n" + String(repeating: "  ", count: indent) }
        output += close
    }

    /// Appends the text between escapes in one piece. Every byte that needs escaping is ASCII, so each piece ends on a
    /// scalar boundary; it is sliced from the UTF-8 view because slicing the string itself would round to characters.
    private static func writeString(_ string: String, to output: inout String) {
        output += "\""
        let utf8 = string.utf8
        var runStart = utf8.startIndex
        for index in utf8.indices {
            let escaped: String
            switch Unicode.Scalar(utf8[index]) {
            case "\"": escaped = "\\\""
            case "\\": escaped = "\\\\"
            case "\n": escaped = "\\n"
            case "\r": escaped = "\\r"
            case "\t": escaped = "\\t"
            case "\u{8}": escaped = "\\b"
            case "\u{c}": escaped = "\\f"
            case let scalar where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                escaped = "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: continue
            }
            output += Substring(utf8[runStart..<index])
            output += escaped
            runStart = utf8.index(after: index)
        }
        output += Substring(utf8[runStart...])
        output += "\""
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(elements.map { (key: $0.0, value: $0.1) }) }
}

extension JSONValue {
    /// Reads the value as a `Decodable` type: `let settings = try payload.decode(Settings.self)`.
    public func decode<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        try JSONDecoder().decode(type, from: Data(serialized().utf8))
    }
}

extension JSONValue: Encodable {
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let items):
            var container = encoder.unkeyedContainer()
            for item in items { try container.encode(item) }
        case .object(let members):
            var container = encoder.container(keyedBy: MemberKey.self)
            for member in members { try container.encode(member.value, forKey: MemberKey(stringValue: member.key)) }
        }
    }

    private struct MemberKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// Decodes any JSON document. A number with a whole value becomes `.int`, however it was written; any other number
/// becomes `.double`.
///
/// Objects decoded with `JSONDecoder` don't keep the document's key order, since `JSONDecoder` doesn't expose it.
extension JSONValue: Decodable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: MemberKey.self) {
            self = .object(try container.allKeys.map { (key: $0.stringValue, value: try container.decode(JSONValue.self, forKey: $0)) })
        } else if var container = try? decoder.unkeyedContainer() {
            var items: [JSONValue] = []
            while !container.isAtEnd { items.append(try container.decode(JSONValue.self)) }
            self = .array(items)
        } else {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }
    }
}

extension JSONValue {
    /// A property's initial value as its default in a schema: `8`, `"draft"`, `[]`, or the raw value of an enum case.
    /// `nil` for a missing value and for one that has no JSON form.
    public static func schemaDefault(_ value: Any?) -> JSONValue? {
        switch value {
        case nil: return nil
        case let value as Bool: return .bool(value)
        case let value as any BinaryInteger: return Int(exactly: value).map(JSONValue.int)
        case let value as Double: return .double(value)
        case let value as Float: return .double(Double(value.description)!)
        case let value as String: return .string(value)
        case let value as any RawRepresentable: return schemaDefault(value.rawValue)
        case let value as any Encodable:
            guard let data = try? OrderedJSONEncoder().encode(value) else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: data)
        default: return nil
        }
    }
}
