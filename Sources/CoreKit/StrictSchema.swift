import Foundation

extension JSONSchema {
    /// The schema in the strict form of OpenAI's structured outputs and tools, exactly as OpenAI's Python SDK writes
    /// it for the same model: every property is required, objects forbid additional properties, optional values are
    /// unions with `null`, and nested models are defined once under `$defs`.
    ///
    /// It is built in that SDK's two steps: the model's JSON schema, then the changes strict mode asks for. A `$ref`
    /// that carries a description is inlined, because strict mode forbids other keys next to a `$ref` and dropping
    /// them would hide the description from the model. Properties keep their declaration order; all other keys are
    /// sorted, and keys added for strict mode follow at the end.
    ///
    /// `[String: T]` maps can't be expressed in strict mode; OpenAI rejects schemas that contain them.
    ///
    /// The second step is a port of the SDK's `_ensure_strict_json_schema` (`openai/lib/_pydantic.py`, Apache-2.0).
    /// `StrictSchemaParityTests` compares the output with what the SDK writes for the pydantic counterparts in
    /// `scripts/strict-schema-fixtures.py`, byte for byte. One difference stays: a definition is keyed and titled with
    /// the schema's name, where pydantic keys a nested class by its short name.
    public func strict() -> JSONValue {
        var writer = StrictSchemaWriter()
        let schema = writer.modelJSONSchema(of: self)
        var expanding: [String] = []
        return schema.ensuringStrict(root: schema, expanding: &expanding)
    }
}

/// Writes the JSON schema of a model: enums in place, optional values as `anyOf` unions with `null`, nested models
/// under `$defs`, and a title on every property and model.
private struct StrictSchemaWriter {
    private typealias Members = [(key: String, value: JSONValue)]

    /// The bounds of an integer type narrower than JSON's integers.
    private static let integerBounds: [String: (minimum: Int?, maximum: Int?)] = [
        "uint8": (0, 255), "uint16": (0, 65535), "uint32": (0, nil), "uint64": (0, nil),
        "int8": (-128, 127), "int16": (-32768, 32767),
    ]
    /// Largest integer a `Double` holds exactly; beyond it, a bound stays a float instead of being rounded.
    private static let maxExactInteger = 9_007_199_254_740_992.0
    /// The string formats OpenAI accepts in strict mode; any other is left out.
    private static let stringFormats: Set<String> = ["date-time", "time", "date", "duration", "email", "hostname", "ipv4", "ipv6", "uuid"]

    private var definitions: [String: JSONValue] = [:]
    /// The definitions that are a tagged union's variant, a payload struct with the tag property added.
    private var taggedVariantNames: Set<String> = []

    mutating func modelJSONSchema(of schema: JSONSchema) -> JSONValue {
        var root = definition(of: schema) ?? inline(schema)
        if !definitions.isEmpty {
            root.append(("$defs", .object(definitions.map { ($0.key, $0.value) })))
        }
        return JSONValue.object(root).sortingKeys(parentKey: nil)
    }

    // MARK: - Private

    /// What a model, a union or a top-level enum is defined as, with its name as the title; `nil` for other schemas.
    private mutating func definition(of schema: JSONSchema) -> Members? {
        switch schema {
        case .object(let name, let description, let properties):
            return object(description: description, properties: properties) + [("title", .string(name))]
        case .enumeration(let name, _, _):
            return inline(schema) + [("title", .string(name))]
        case .union(let name, let description, let variants):
            return Self.described(description) + [("anyOf", .array(variants.map { .object(inline($0)) })), ("title", .string(name))]
        case .taggedUnion(let name, let description, let tag, let variants):
            let references = variants.map { JSONValue.object(taggedVariant($0.schema, tag: (tag, $0.tagValue))) }
            return Self.described(description) + [("anyOf", .array(references)), ("title", .string(name))]
        default:
            return nil
        }
    }

    /// - Parameter tag: A tagged union's tag key and value, written as the last property and the first required one.
    private mutating func object(
        description: String?,
        properties: [JSONSchema.Property],
        tag: (key: String, value: String)? = nil
    ) -> Members {
        var fields: Members = properties.map { property in
            var field = Self.described(property.description)
            let schema = inline(property.schema)
            // The property's own description replaces the one of its type.
            field += schema.filter { $0.key != "description" || property.description == nil }
            if let defaultValue = property.defaultValue {
                field.append(("default", defaultValue))
            }
            // A property that points at a model takes over the model's title when it is inlined.
            if !Self.referencesDefinition(schema) {
                field.append(("title", .string(Self.fieldTitle(property.key))))
            }
            return (property.key, .object(field))
        }
        // A model's own schema leaves a property with a default out of `required`, which decides where the key ends up.
        var required = properties.filter(\.isRequired).map { JSONValue.string($0.key) }
        if let tag {
            fields.append((tag.key, ["type": "string", "const": .string(tag.value), "title": .string(Self.fieldTitle(tag.key))]))
            required.insert(.string(tag.key), at: 0)
        }

        var members = Self.described(description)
        members += [("type", "object"), ("properties", .object(fields)), ("additionalProperties", false)]
        if !required.isEmpty {
            members.append(("required", .array(required)))
        }
        return members
    }

    /// The schema as it stands inside another one: a property, an array's items or a union's variant.
    private mutating func inline(_ schema: JSONSchema) -> Members {
        switch schema {
        case .string(let format):
            let format = format.flatMap { Self.stringFormats.contains($0) ? $0 : nil }
            return [("type", "string")] + (format.map { [("format", .string($0))] } ?? [])
        case .integer(let format):
            var members: Members = [("type", "integer")]
            if let bounds = format.flatMap({ Self.integerBounds[$0] }) {
                if let minimum = bounds.minimum { members.append(("minimum", .int(minimum))) }
                if let maximum = bounds.maximum { members.append(("maximum", .int(maximum))) }
            }
            return members
        case .number:
            return [("type", "number")]
        case .boolean:
            return [("type", "boolean")]
        case .any:
            return []
        case .array(let items):
            return [("type", "array"), ("items", .object(inline(items)))]
        case .map(let values):
            return [("type", "object"), ("additionalProperties", .object(inline(values)))]
        case .enumeration(_, let description, let values):
            let type: JSONValue = if case .int = values.first { "integer" } else { "string" }
            return Self.described(description) + [("type", type), ("enum", .array(values))]
        case .object(let name, _, _), .union(let name, _, _), .taggedUnion(let name, _, _, _):
            precondition(!taggedVariantNames.contains(name), Self.sharedVariantMessage(name))
            if definitions[name] == nil {
                // Reserves the name first, so a model that contains itself ends in a reference.
                definitions[name] = .null
                definitions[name] = definition(of: schema).map { .object($0) }
            }
            return [("$ref", .string("#/$defs/" + Self.encodedReferenceName(name)))]
        case .nullable(let wrapped):
            let value = inline(wrapped)
            // A value of any type, or one that is a union with `null` already, needs no union.
            let hasType = value.contains { $0.key == "type" || $0.key == "$ref" }
            return hasType ? [("anyOf", [.object(value), ["type": "null"]])] : value
        case .constrained(.nullable(let wrapped), let rules):
            return inline(.nullable(.constrained(wrapped, by: rules)))
        case .constrained(.constrained(let wrapped, let inner), let rules):
            return inline(.constrained(wrapped, by: inner + rules))
        case .constrained(let wrapped, let rules):
            var members = inline(wrapped)
            let isInteger = members.contains { $0.key == "type" && $0.value.string == "integer" }
            for rule in rules {
                let (key, value): (String, JSONValue) =
                    switch rule {
                    case .minLength(let count): ("minLength", .int(count))
                    case .maxLength(let count): ("maxLength", .int(count))
                    case .minItems(let count): ("minItems", .int(count))
                    case .maxItems(let count): ("maxItems", .int(count))
                    case .minimum(let bound): ("minimum", Self.bound(bound, isInteger: isInteger))
                    case .maximum(let bound): ("maximum", Self.bound(bound, isInteger: isInteger))
                    case .pattern(let pattern): ("pattern", .string(pattern))
                    case .items: preconditionFailure("item rules are part of the items' schema")
                    }
                members.removeAll { $0.key == key }
                members.append((key, value))
            }
            return members
        }
    }

    /// A tagged union's variant, defined under its payload struct's name as that struct plus the tag property, as
    /// pydantic defines a variant model with a `Literal` tag field.
    private mutating func taggedVariant(_ payload: JSONSchema, tag: (key: String, value: String)) -> Members {
        guard case .object(let name, let description, let properties) = payload else { return inline(payload) }
        let definition = JSONValue.object(object(description: description, properties: properties, tag: tag) + [("title", .string(name))])
        let isSameVariant = definitions[name].map { taggedVariantNames.contains(name) && $0.serialized() == definition.serialized() }
        precondition(isSameVariant ?? true, Self.sharedVariantMessage(name))
        taggedVariantNames.insert(name)
        definitions[name] = definition
        return [("$ref", .string("#/$defs/" + Self.encodedReferenceName(name)))]
    }

    /// A definition has one body, so a struct can't be a tagged variant and also appear on its own or with another tag.
    private static func sharedVariantMessage(_ name: String) -> String {
        "'\(name)' is a tagged union's variant and also appears on its own or with another tag in the same strict schema"
    }

    /// The lines of a wrapped doc comment joined with spaces, with blank-line paragraph breaks kept.
    private static func described(_ description: String?) -> Members {
        guard let description else { return [] }
        let paragraphs = description.split(separator: "\n\n", omittingEmptySubsequences: false)
        return [("description", .string(paragraphs.map { $0.replacing("\n", with: " ") }.joined(separator: "\n\n")))]
    }

    private static func referencesDefinition(_ members: Members) -> Bool {
        members.contains { key, value in
            key == "$ref" || (key == "anyOf" && value.array?.contains { $0.object?["$ref"] != nil } == true)
        }
    }

    /// Capitalizes every letter that follows a non-letter and lowercases the rest, then turns underscores into spaces:
    /// `html2text` → `Html2Text`, `page_size` → `Page Size`, `type_` → `Type`.
    private static func fieldTitle(_ name: String) -> String {
        var title = ""
        var afterLetter = false
        for scalar in name.unicodeScalars {
            if scalar.properties.isAlphabetic {
                title += afterLetter ? scalar.properties.lowercaseMapping : scalar.properties.uppercaseMapping
                afterLetter = true
            } else {
                title.unicodeScalars.append(scalar == "_" ? " " : scalar)
                afterLetter = false
            }
        }
        return title.trimmingWhitespace()
    }

    /// A whole bound is written without a fraction (`90`, not `90.0`).
    private static func bound(_ bound: Double, isInteger: Bool) -> JSONValue {
        if isInteger, let whole = Int(exactly: bound) {
            return .int(whole)
        }
        return bound == bound.rounded(.towardZero) && abs(bound) <= maxExactInteger ? .int(Int(bound)) : .double(bound)
    }

    /// A definition's name inside a `$ref`: escaped for a JSON pointer, then percent-encoded for a URL fragment.
    private static func encodedReferenceName(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "!$&'()*+,-./:;=?@_~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return name.replacing("~", with: "~0").replacing("/", with: "~1").addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }
}

/// A schema object whose keys keep their order.
private struct SchemaObject {
    var members: [(key: String, value: JSONValue)]

    var json: JSONValue { .object(members) }

    subscript(key: String) -> JSONValue? {
        members.first { $0.key == key }?.value
    }

    /// Replaces the value of `key` where it stands, or adds the key at the end.
    mutating func set(_ key: String, _ value: JSONValue) {
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index].value = value
        } else {
            members.append((key, value))
        }
    }

    mutating func remove(_ key: String) {
        members.removeAll { $0.key == key }
    }

    /// Adds the keys of `source` that this object lacks; its own keys win.
    mutating func mergeMissing(_ source: SchemaObject) {
        for member in source.members where self[member.key] == nil {
            members.append(member)
        }
    }
}

extension JSONValue {
    fileprivate var object: SchemaObject? {
        if case .object(let members) = self { SchemaObject(members: members) } else { nil }
    }

    fileprivate var array: [JSONValue]? {
        if case .array(let items) = self { items } else { nil }
    }

    fileprivate var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// Sorts object keys by their bytes, except the property list and default values, which keep their order.
    fileprivate func sortingKeys(parentKey: String?) -> JSONValue {
        switch self {
        case .object(var members):
            if parentKey != "properties" && parentKey != "default" {
                members.sort { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            }
            return .object(members.map { ($0.key, $0.value.sortingKeys(parentKey: $0.key)) })
        case .array(let items):
            return .array(items.map { $0.sortingKeys(parentKey: parentKey) })
        default:
            return self
        }
    }

    /// OpenAI's strict mode: closed objects whose properties are all required, no `null` defaults, and no `$ref` next
    /// to other keys. A port of the SDK's `_ensure_strict_json_schema`.
    ///
    /// - Parameter expanding: The references being inlined around this schema.
    fileprivate func ensuringStrict(root: JSONValue, expanding: inout [String]) -> JSONValue {
        guard var object else { return self }

        for key in ["$defs", "definitions"] {
            if let definitions = object[key]?.object {
                object.set(key, .object(definitions.members.map { ($0.key, $0.value.ensuringStrict(root: root, expanding: &expanding)) }))
            }
        }

        if object["type"]?.string == "object", object["additionalProperties"] == nil {
            object.set("additionalProperties", false)
        }

        if let properties = object["properties"]?.object {
            let required = properties.members.map { JSONValue.string($0.key) }
            object.set(
                "properties", .object(properties.members.map { ($0.key, $0.value.ensuringStrict(root: root, expanding: &expanding)) }))
            object.set("required", .array(required))
        }

        if let items = object["items"], items.object != nil {
            object.set("items", items.ensuringStrict(root: root, expanding: &expanding))
        }

        if let variants = object["anyOf"]?.array {
            object.set("anyOf", .array(variants.map { $0.ensuringStrict(root: root, expanding: &expanding) }))
        }

        if let entries = object["allOf"]?.array {
            if entries.count == 1 {
                let entry = entries[0].ensuringStrict(root: root, expanding: &expanding)
                object.remove("allOf")
                for member in entry.object?.members ?? [] {
                    object.set(member.key, member.value)
                }
            } else {
                object.set("allOf", .array(entries.map { $0.ensuringStrict(root: root, expanding: &expanding) }))
            }
        }

        if case .null? = object["default"] {
            object.remove("default")
        }

        guard let reference = object["$ref"]?.string, object.members.count > 1 else { return object.json }
        // A type that contains itself through documented fields would be inlined forever; the recursive reference
        // stays bare instead.
        if expanding.contains(reference) {
            return ["$ref": .string(reference)]
        }
        guard let resolved = root.definition(for: reference) else {
            preconditionFailure("schema reference \(reference) does not resolve")
        }
        object.remove("$ref")
        object.mergeMissing(resolved)
        expanding.append(reference)
        defer { expanding.removeLast() }
        return object.json.ensuringStrict(root: root, expanding: &expanding)
    }

    /// The definition that a `$ref` such as `#/$defs/Work%20Mode` points at. The `$ref` percent-encodes the name,
    /// while the keys of `$defs` stay as written.
    private func definition(for reference: String) -> SchemaObject? {
        let pointer = reference.removingPercentEncoding ?? reference
        guard pointer.hasPrefix("#/$defs/") else { return nil }
        let name = pointer.dropFirst("#/$defs/".count).replacing("~1", with: "/").replacing("~0", with: "~")
        return object?["$defs"]?.object?[String(name)]?.object
    }
}
