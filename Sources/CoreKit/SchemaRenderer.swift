extension JSONSchema {
    /// The schema as JSON with every named schema inlined.
    public var json: JSONValue {
        var renderer = SchemaRenderer(mode: .inline)
        return renderer.render(self)
    }
}

/// Renders ``JSONSchema`` values to JSON.
package struct SchemaRenderer {
    package enum Mode {
        case inline
        /// Named schemas are collected in ``components`` and replaced by `$ref`s.
        case components
    }

    let mode: Mode
    package private(set) var components: [String: JSONValue] = [:]
    /// Names used by schemas with different definitions.
    package private(set) var conflictingNames: Set<String> = []

    package init(mode: Mode) {
        self.mode = mode
    }

    package mutating func render(_ schema: JSONSchema) -> JSONValue {
        switch schema {
        case .string(let format): primitive("string", format: format)
        case .integer(let format): primitive("integer", format: format)
        case .number(let format): primitive("number", format: format)
        case .boolean: primitive("boolean", format: nil)
        case .any: [:]
        case .array(let items): ["type": "array", "items": render(items)]
        case .map(let values): ["type": "object", "additionalProperties": render(values)]
        case .object(let name, let description, let properties):
            named(name, objectBody(description: description, properties: properties))
        case .enumeration(let name, let description, let values):
            named(name, enumerationBody(description: description, values: values))
        case .union(let name, let description, let variants):
            named(name, unionBody(description: description, variants: variants.map { render($0) }))
        case .taggedUnion(let name, let description, let tag, let variants):
            named(
                name,
                unionBody(
                    description: description,
                    variants: variants.map { taggedVariantBody(tag: (tag, $0.tagValue), payload: $0.schema) }
                )
            )
        case .nullable(let wrapped): renderNullable(wrapped)
        case .constrained(let wrapped, let rules): withKeywords(of: rules, render(wrapped))
        }
    }

    private mutating func renderNullable(_ wrapped: JSONSchema) -> JSONValue {
        switch wrapped {
        case .string(let format): primitive("string", format: format, nullable: true)
        case .integer(let format): primitive("integer", format: format, nullable: true)
        case .number(let format): primitive("number", format: format, nullable: true)
        case .boolean: primitive("boolean", format: nil, nullable: true)
        case .any: [:]
        case .nullable(let inner): renderNullable(inner)
        default: ["anyOf": [render(wrapped), ["type": "null"]]]
        }
    }

    private func primitive(_ type: String, format: String?, nullable: Bool = false) -> JSONValue {
        var members: [(key: String, value: JSONValue)] = [("type", nullable ? [.string(type), "null"] : .string(type))]
        if let format { members.append(("format", .string(format))) }
        return .object(members)
    }

    /// - Parameter tag: A tagged union's tag key and value, rendered as the first, required property.
    private mutating func objectBody(
        description: String?,
        properties: [JSONSchema.Property],
        tag: (key: String, value: String)? = nil
    ) -> JSONValue {
        var members: [(key: String, value: JSONValue)] = [("type", "object")]
        if let description { members.append(("description", .string(description))) }
        var renderedProperties = properties.map { property in
            (key: property.key, value: withDescription(property.description, render(property.schema)))
        }
        var required = properties.filter(\.isRequired).map { JSONValue.string($0.key) }
        if let tag {
            renderedProperties.insert((tag.key, ["type": "string", "enum": [.string(tag.value)]]), at: 0)
            required.insert(.string(tag.key), at: 0)
        }
        members.append(("properties", .object(renderedProperties)))
        if !required.isEmpty { members.append(("required", .array(required))) }
        return .object(members)
    }

    /// The payload struct's object with the tag property added; inlined even in OpenAPI components.
    private mutating func taggedVariantBody(tag: (key: String, value: String), payload: JSONSchema) -> JSONValue {
        guard case .object(_, let description, let properties) = payload else {
            preconditionFailure("Tagged union variants must be @Schema structs, but '\(tag.value)' isn't")
        }
        return objectBody(description: description, properties: properties, tag: tag)
    }

    private func unionBody(description: String?, variants: [JSONValue]) -> JSONValue {
        var members: [(key: String, value: JSONValue)] = []
        if let description { members.append(("description", .string(description))) }
        members.append(("anyOf", .array(variants)))
        return .object(members)
    }

    private func enumerationBody(description: String?, values: [JSONValue]) -> JSONValue {
        let type: JSONValue = if case .int = values.first { "integer" } else { "string" }
        var members: [(key: String, value: JSONValue)] = [("type", type)]
        if let description { members.append(("description", .string(description))) }
        members.append(("enum", .array(values)))
        return .object(members)
    }

    private mutating func named(_ name: String, _ body: JSONValue) -> JSONValue {
        guard mode == .components else { return body }
        if let existing = components[name] {
            if existing.serialized() != body.serialized() { conflictingNames.insert(name) }
        } else {
            components[name] = body
        }
        return ["$ref": .string("#/components/schemas/\(name)")]
    }

    private func withKeywords(of rules: [ValidationRule], _ schema: JSONValue) -> JSONValue {
        guard case .object(let members) = schema else { return schema }
        return .object(members + rules.map(\.keyword))
    }

    /// The property's description replaces the one of its type.
    private func withDescription(_ description: String?, _ schema: JSONValue) -> JSONValue {
        guard let description, case .object(let members) = schema else { return schema }
        return .object(members.filter { $0.key != "description" } + [("description", .string(description))])
    }
}
