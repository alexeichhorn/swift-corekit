public import Foundation

/// Encodes values to JSON with object keys in the order the type encodes them, which for synthesized `Codable` is
/// declaration order; `JSONEncoder` doesn't keep it.
///
/// `URL` and `Data` are written as `JSONEncoder` writes them, as the absolute string and as Base64.
///
/// - Warning: It is 1.3 to 3 times slower than `JSONEncoder`, more so with many short values or many escapes. Use it
///   where key order or the exact bytes matter, and `JSONEncoder` for everything else.
public struct OrderedJSONEncoder: Sendable {
    /// Leaves a `nil` property out instead of writing it as `null`.
    public var omitsNil: Bool
    /// Puts every member on its own line, indented by two spaces.
    public var prettyPrinted: Bool
    public var dateEncoding: DateEncoding
    /// Writes a `UUID` in lowercase instead of uppercase, which is what `JSONEncoder` writes.
    public var lowercaseUUIDs: Bool

    public enum DateEncoding: Sendable {
        /// `2026-01-02T03:04:05Z`, as everywhere in corekit's JSON coding.
        case iso8601
        case custom(@Sendable (Date) -> JSONValue)
    }

    public init(
        omitsNil: Bool = false,
        prettyPrinted: Bool = false,
        dateEncoding: DateEncoding = .iso8601,
        lowercaseUUIDs: Bool = false
    ) {
        self.omitsNil = omitsNil
        self.prettyPrinted = prettyPrinted
        self.dateEncoding = dateEncoding
        self.lowercaseUUIDs = lowercaseUUIDs
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        Data(try jsonValue(value).serialized(pretty: prettyPrinted).utf8)
    }

    /// The value as a `JSONValue` instead of bytes, to put it into a larger JSON value or to store it as one.
    public func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let node = Node()
        try NodeEncoder(node: node, codingPath: [], options: self).encode(value)
        return node.jsonValue
    }
}

/// A JSON value being built. A class, so a container handed out earlier keeps filling the same value.
private final class Node {
    var scalar: JSONValue?
    var isArray = false
    var items: [Node] = []
    private var members: [(key: String, node: Node)] = []
    private var memberIndices: [String: Int] = [:]

    /// A key encoded again keeps its place and takes the new value.
    func setMember(_ node: Node, for key: String) {
        if let index = memberIndices[key] {
            members[index].node = node
        } else {
            memberIndices[key] = members.count
            members.append((key, node))
        }
    }

    func member(for key: String) -> Node? {
        memberIndices[key].map { members[$0].node }
    }

    /// A node nothing was encoded into is an empty object, as with `JSONEncoder`.
    var jsonValue: JSONValue {
        if let scalar { return scalar }
        return isArray ? .array(items.map(\.jsonValue)) : .object(members.map { ($0.key, $0.node.jsonValue) })
    }
}

private struct NodeEncoder: Encoder {
    let node: Node
    let codingPath: [any CodingKey]
    let options: OrderedJSONEncoder
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(KeyedContainer(encoder: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        node.isArray = true
        return UnkeyedContainer(encoder: self)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleValueContainer(encoder: self)
    }

    /// Writes scalars directly; every other value encodes itself into this encoder's containers.
    func encode(_ value: some Encodable) throws {
        switch value {
        case let value as String: node.scalar = .string(value)
        case let value as Bool: node.scalar = .bool(value)
        case let value as Double: node.scalar = .double(try finite(value))
        // Through the description, so 0.1 isn't written as 0.10000000149011612.
        case let value as Float: node.scalar = .double(try finite(Double(value.description)!))
        case let value as any BinaryInteger: node.scalar = .int(try int(value))
        case let value as Decimal: node.scalar = try number(value)
        case let value as Date:
            switch options.dateEncoding {
            case .iso8601: node.scalar = .string(value.formatted(.iso8601))
            case .custom(let encode): node.scalar = encode(value)
            }
        case let value as UUID: node.scalar = .string(options.lowercaseUUIDs ? value.uuidString.lowercased() : value.uuidString)
        case let value as URL: node.scalar = .string(value.absoluteString)
        case let value as Data: node.scalar = .string(value.base64EncodedString())
        default: try value.encode(to: self)
        }
    }

    func child(_ node: Node, at key: any CodingKey) -> NodeEncoder {
        NodeEncoder(node: node, codingPath: codingPath + [key], options: options)
    }

    private func finite(_ value: Double) throws -> Double {
        guard value.isFinite else { throw invalidValue(value, "JSON has no representation for \(value)") }
        return value
    }

    /// A `Decimal` as a JSON number, like `JSONEncoder` writes it: `12.34`, and `5` for a whole one. Digits beyond
    /// the 17 a `Double` holds are rounded.
    private func number(_ value: Decimal) throws -> JSONValue {
        let text = value.description
        if let int = Int(text) {
            return .int(int)
        }
        guard let double = Double(text) else { throw invalidValue(value, "JSON has no representation for \(value)") }
        return .double(try finite(double))
    }

    private func int(_ value: some BinaryInteger) throws -> Int {
        guard let int = Int(exactly: value) else { throw invalidValue(value, "\(value) doesn't fit in Int") }
        return int
    }

    private func invalidValue(_ value: Any, _ description: String) -> EncodingError {
        .invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: description))
    }
}

private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: NodeEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }

    mutating func encodeNil(forKey key: Key) throws { child(key).node.scalar = .null }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try child(key).encode(value) }

    // Synthesized `Codable` encodes Optional properties through these, and their default implementations skip `nil`.
    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int128?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt128?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }
    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws { try encodeOptional(value, forKey: key) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<
        NestedKey
    > {
        container(at: key).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer { container(at: key).unkeyedContainer() }
    mutating func superEncoder() -> any Encoder { container(at: PathKey(stringValue: "super")) }
    mutating func superEncoder(forKey key: Key) -> any Encoder { container(at: key) }

    private mutating func encodeOptional(_ value: (some Encodable)?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else if !encoder.options.omitsNil {
            try encodeNil(forKey: key)
        }
    }

    private func child(_ key: any CodingKey) -> NodeEncoder {
        let node = Node()
        encoder.node.setMember(node, for: key.stringValue)
        return encoder.child(node, at: key)
    }

    /// A container asked for a second time continues the first one instead of replacing it.
    private func container(at key: any CodingKey) -> NodeEncoder {
        if let node = encoder.node.member(for: key.stringValue), node.scalar == nil { return encoder.child(node, at: key) }
        return child(key)
    }
}

private struct UnkeyedContainer: UnkeyedEncodingContainer {
    let encoder: NodeEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }
    var count: Int { encoder.node.items.count }

    mutating func encodeNil() throws { child().node.scalar = .null }
    mutating func encode<T: Encodable>(_ value: T) throws { try child().encode(value) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        child().container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer { child().unkeyedContainer() }
    mutating func superEncoder() -> any Encoder { child() }

    private func child() -> NodeEncoder {
        let node = Node()
        encoder.node.items.append(node)
        return encoder.child(node, at: PathKey(intValue: count - 1))
    }
}

private struct SingleValueContainer: SingleValueEncodingContainer {
    let encoder: NodeEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }

    mutating func encodeNil() throws { encoder.node.scalar = .null }
    mutating func encode<T: Encodable>(_ value: T) throws { try encoder.encode(value) }
}

/// An array index or the `super` key in a coding path.
private struct PathKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
