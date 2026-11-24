public import Hummingbird

/// A handler parameter resolved from the request, e.g. the authenticated user.
public protocol RequestResolvable: Sendable {
    static func resolve(from request: Request) async throws -> Self

    /// Documented as required by every operation that takes this parameter.
    static var openAPISecurity: OpenAPISecurityScheme? { get }
}

extension RequestResolvable {
    public static var openAPISecurity: OpenAPISecurityScheme? { nil }
}
