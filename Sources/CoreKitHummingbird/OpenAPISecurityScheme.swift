public import CoreKit

/// An OpenAPI security scheme, listed under `components/securitySchemes` and required by the operations that use it.
public struct OpenAPISecurityScheme: Sendable {
    /// The key in `components/securitySchemes`.
    public let name: String
    let definition: JSONValue

    /// `Authorization: Bearer <token>`.
    public static func bearer(name: String = "BearerAuth", format: String? = nil, description: String? = nil) -> Self {
        var members: [(key: String, value: JSONValue)] = [("type", "http"), ("scheme", "bearer")]
        if let format { members.append(("bearerFormat", .string(format))) }
        if let description { members.append(("description", .string(description))) }
        return Self(name: name, definition: .object(members))
    }
}
