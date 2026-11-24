/// Groups operations in Swagger UI. Declare tags as static members: `static let orders = OpenAPITag("Orders")`.
public struct OpenAPITag: Sendable, Hashable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}
