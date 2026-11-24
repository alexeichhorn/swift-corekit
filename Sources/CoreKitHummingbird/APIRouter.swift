/// Routes under a path prefix, like FastAPI's `APIRouter`.
///
/// Declare routers as global constants, attach top-level handler functions with `@GET(router, "/path")`, `@POST`, ...
/// and include child routers, which are mounted below this router's prefix:
///
/// ```swift
/// let orderRouter = APIRouter("/orders", tag: .orders, include: [orderActivityRouter])
///
/// @POST(orderRouter, "/")
/// func createOrder(user: AuthUser, body: CreateOrderInput) async throws -> OrderResponse { ... }
/// ```
public final class APIRouter: Sendable {
    let prefix: String
    /// `nil` uses the including router's tag.
    let tag: OpenAPITag?
    let includedRouters: [APIRouter]

    public init(_ prefix: String, tag: OpenAPITag? = nil, include routers: [APIRouter] = []) {
        self.prefix = prefix
        self.tag = tag
        self.includedRouters = routers
    }
}
