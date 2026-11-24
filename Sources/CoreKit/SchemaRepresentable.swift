import Foundation

/// A type that describes its JSON wire format. Conform with `@Schema`.
public protocol SchemaRepresentable {
    static var jsonSchema: JSONSchema { get }

    /// Appends an issue for each of `rules` this value violates, and for every violated rule of the values nested in it.
    ///
    /// `path` leads to this value. `@Schema` generates the implementation; types without constraints or nested values
    /// keep the default, which finds nothing.
    func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue])
}

extension String: SchemaRepresentable { public static var jsonSchema: JSONSchema { .string() } }
extension Bool: SchemaRepresentable { public static var jsonSchema: JSONSchema { .boolean } }

extension Int: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "int64") } }
extension Int64: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "int64") } }
extension Int32: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "int32") } }
extension Int16: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "int16") } }
extension Int8: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "int8") } }
extension UInt: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "uint64") } }
extension UInt64: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "uint64") } }
extension UInt32: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "uint32") } }
extension UInt16: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "uint16") } }
extension UInt8: SchemaRepresentable { public static var jsonSchema: JSONSchema { .integer(format: "uint8") } }

extension Double: SchemaRepresentable { public static var jsonSchema: JSONSchema { .number(format: "double") } }
extension Float: SchemaRepresentable { public static var jsonSchema: JSONSchema { .number(format: "float") } }

/// Encoded as ISO-8601, the date strategy of corekit's JSON coding.
extension Date: SchemaRepresentable { public static var jsonSchema: JSONSchema { .string(format: "date-time") } }
extension UUID: SchemaRepresentable { public static var jsonSchema: JSONSchema { .string(format: "uuid") } }
extension URL: SchemaRepresentable { public static var jsonSchema: JSONSchema { .string(format: "uri") } }

/// Untyped JSON. OpenAI's strict mode rejects a schema that allows any value.
extension JSONValue: SchemaRepresentable { public static var jsonSchema: JSONSchema { .any } }

extension Optional: SchemaRepresentable where Wrapped: SchemaRepresentable {
    public static var jsonSchema: JSONSchema { .nullable(Wrapped.jsonSchema) }
}

extension Array: SchemaRepresentable where Element: SchemaRepresentable {
    public static var jsonSchema: JSONSchema { .array(items: Element.jsonSchema) }
}

extension Dictionary: SchemaRepresentable where Key == String, Value: SchemaRepresentable {
    public static var jsonSchema: JSONSchema { .map(values: Value.jsonSchema) }
}
