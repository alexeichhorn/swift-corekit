public import CoreKit
public import Hummingbird

/// The application's routes and the OpenAPI document derived from them.
///
/// ```swift
/// try OpenAPIDocument(title: "Shop API", version: "0.1.0", errorResponse: ErrorResponse.self, routers: [orderRouter])
///     .register(on: router)
/// ```
public struct OpenAPIDocument: Sendable {
    let title: String
    let version: String
    let errorSchema: JSONSchema?
    /// Every endpoint with its full path and its router's tag, grouped by router.
    let endpoints: [Endpoint]

    /// - Parameters:
    ///   - errorResponse: Documented as the `default` response of every operation.
    ///   - routers: The top-level routers, like FastAPI's `app.include_router`. Every `@GET`/`@POST`/... handler in the
    ///     process must be attached to one of them or to a router they include.
    /// - Throws: When a handler's router isn't included anywhere, or a router is included twice.
    public init(title: String, version: String, errorResponse: (any SchemaRepresentable.Type)? = nil, routers: [APIRouter]) throws {
        self.title = title
        self.version = version
        self.errorSchema = errorResponse?.jsonSchema

        var mounts: [ObjectIdentifier: (order: Int, prefix: String, tag: OpenAPITag?)] = [:]
        func mount(_ router: APIRouter, under parentPrefix: String, tag parentTag: OpenAPITag?) throws {
            guard mounts[ObjectIdentifier(router)] == nil else {
                throw OpenAPIDocumentError(description: "The router for '\(router.prefix)' is included twice")
            }
            let prefix = Self.joinedPath(parentPrefix, router.prefix)
            let tag = router.tag ?? parentTag
            mounts[ObjectIdentifier(router)] = (mounts.count, prefix, tag)
            for child in router.includedRouters { try mount(child, under: prefix, tag: tag) }
        }
        for router in routers { try mount(router, under: "", tag: nil) }

        let mounted = try RouteRegistration.all().map { registration in
            guard let mount = mounts[ObjectIdentifier(registration.router)] else {
                throw OpenAPIDocumentError(
                    description:
                        "'\(registration.endpoint.operationID)' is attached to the router for '\(registration.router.prefix)', which isn't included"
                )
            }
            var endpoint = registration.endpoint
            endpoint.path = Self.joinedPath(mount.prefix, endpoint.path)
            endpoint.tag = mount.tag
            return (order: mount.order, endpoint: endpoint)
        }
        // Stable, so each router keeps its section order (declaration order within a file).
        self.endpoints = mounted.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element.endpoint)
    }

    /// Registers every endpoint plus `GET /openapi.json` and `GET /docs` (Swagger UI).
    ///
    /// - Parameter docs: `false` leaves out `/openapi.json` and `/docs`, for a service that shouldn't publish its API.
    /// - Throws: When two endpoints share a method and path or two different schemas share a name.
    public func register(on router: Router<BasicRequestContext>, docs: Bool = true) throws {
        let documentJSON = try json().serialized()
        let docsHTML = swaggerUIHTML(title: title, documentPath: "/openapi.json")
        for endpoint in endpoints {
            let method: HTTPRequest.Method =
                switch endpoint.method {
                case .get: .get
                case .post: .post
                case .put: .put
                case .patch: .patch
                case .delete: .delete
                }
            router.on(RouterPath(endpoint.path), method: method, use: endpoint.handler)
            if endpoint.answersHead {
                router.head(RouterPath(endpoint.path)) { request, context in
                    let response = try await endpoint.handler(request, context)
                    var head = response.createHeadResponse()
                    // A streamed body has no length, and the empty body here would announce one of zero.
                    if !response.headers.contains(.contentLength) { head.headers[.contentLength] = nil }
                    return head
                }
            }
        }
        guard docs else { return }
        router.get("openapi.json") { _, _ in
            Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(string: documentJSON)))
        }
        router.get("docs") { _, _ in
            Response(
                status: .ok, headers: [.contentType: "text/html; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: docsHTML)))
        }
    }

    /// A `/` path stands for the prefix itself, so `"/"` under `"/orders"` is `"/orders"`.
    private static func joinedPath(_ prefix: String, _ path: String) -> String {
        guard path != "/" else { return prefix.isEmpty ? "/" : prefix }
        return prefix + path
    }
}
