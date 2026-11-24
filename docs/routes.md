# Routes

`CoreKitHummingbird` gives Hummingbird 2 FastAPI-style routers and handler functions. The OpenAPI document at
`/openapi.json` and Swagger UI at `/docs` are derived from the handlers.

```swift
.product(name: "CoreKitHummingbird", package: "swift-corekit")
```

```swift
import CoreKit
import CoreKitHummingbird
import Hummingbird

extension OpenAPITag {
    static let orders = OpenAPITag("Orders")
    static let orderActivity = OpenAPITag("Order Activity")
}

struct AuthUser: RequestResolvable {
    let id: String

    static func resolve(from request: Request) async throws -> AuthUser {
        guard let token = request.headers[.authorization]?.trimmingPrefix("Bearer ") else { throw HTTPError(.unauthorized) }
        return AuthUser(id: String(token))
    }

    static var openAPISecurity: OpenAPISecurityScheme? { .bearer(format: "user-id") }
}

// OrderRoutes.swift
let orderRouter = APIRouter("/orders", tag: .orders, include: [orderActivityRouter])

/// Creates an order.
@POST(orderRouter, "/")
func createOrder(user: AuthUser, body: CreateOrderInput) async throws -> OrderResponse { ... }

@GET(orderRouter, "/")
func listOrders(user: AuthUser, query: ListOrdersQuery) async throws -> [OrderResponse] { ... }

@POST(orderRouter, "/:orderID/cancel")
func cancelOrder(user: AuthUser, orderID: Int64) async throws -> OrderResponse? { ... }

@DELETE(orderRouter, "/:orderID")
func deleteOrder(user: AuthUser, orderID: Int64) async throws { ... }

@POST(orderRouter, "/payments/webhook")
func handlePaymentWebhook(request: Request) async throws -> Response { ... }

/// Attaches a receipt; bodies up to 10 MB instead of Hummingbird's 2 MB default.
@POST(orderRouter, "/:orderID/receipts", maxBodySize: "10mb")
func attachReceipt(user: AuthUser, orderID: Int64, form: ReceiptForm) async throws -> OrderResponse { ... }

@Schema
struct ReceiptForm: Codable, Sendable {
    /// Shown as a file picker in Swagger UI.
    let file: UploadedFile  // filename, contentType, data
}

// OrderActivityRoutes.swift
let orderActivityRouter = APIRouter("/activity", tag: .orderActivity)

@GET(orderActivityRouter, "/:orderID")
func listOrderActivity(orderID: Int64) async throws -> [OrderActivityResponse] { ... }

// App setup: the top-level routers, like FastAPI's `app.include_router`
let openAPI = try OpenAPIDocument(
    title: "Shop API",
    version: "0.1.0",
    errorResponse: ErrorResponse.self,
    routers: [orderRouter]
)
let router = Router()
try openAPI.register(on: router)  // routes + GET /openapi.json + GET /docs
let app = Application(router: router)
```

## Parameters

Handler parameters bind by shape:

| Parameter | Source |
| --- | --- |
| name matches a `:name` path segment | path parameter (`LosslessStringConvertible` or `UUID`); unparsable → 400 |
| label `body` | JSON body (`Decodable & SchemaRepresentable`), whatever the `Content-Type`; one that does not decode → 400 (`InvalidRequestBodyError`) |
| label `form` | `multipart/form-data` body (`Decodable & SchemaRepresentable`); other content types → 415, malformed → 400 |
| label `query` | URL query decoded into a `@Schema` struct; each property is a documented query parameter; one that does not decode → 400 |
| type `Request` | the raw request, undocumented |
| any other type | `RequestResolvable.resolve(from:)`; its `openAPISecurity` is required by the operation |

## Responses

A `SchemaRepresentable & Encodable` return value is 200 JSON, `Void` is 204, and `Response` is returned as built and
documented without a schema. For JSON with another status, return `try Response(status: .created, json: value)`.

The JSON is what serde and pydantic write: an unset property is `null`, keys keep their declaration order, UUIDs are
lowercase, and dates are UTC with `Z` and a fraction only when they have one (`2026-01-02T03:04:05.123Z`).
`RouteBinding.responseEncoder` is that encoder. An integer has to fit in `Int`, as with `OrderedJSONEncoder`. JSON
bodies are decoded with ISO-8601 dates, matching the schemas.

## Routers and discovery

- Handlers are top-level functions, so their names are unique across the module; the operation ID is the name in
  snake_case (`createOrder` → `create_order`).
- Routers are global constants. `include:` mounts child routers under the parent prefix, so a child declares only its
  local prefix; a router without a `tag:` uses its parent's. A `/` path is the prefix itself (`/orders`, not
  `/orders/`).
- Handlers aren't listed anywhere: each route macro stores a record in a section of the binary, and `OpenAPIDocument`
  reads them at startup, the way Swift Testing finds `@Test` functions. On macOS the section is found through dyld;
  on Linux the small C target `CCoreKitRoutes` reads the ELF section's bounds. `OpenAPIDocument` throws when a
  handler's router isn't reachable from `routers`, or a router is included twice. Since every handler in the process
  is found, every document of the process has to include every router.
- Doc comments on handlers become operation summaries.
- Thrown errors go through the router's middleware; map your own error type in a `RouterMiddleware`. `errorResponse`
  documents the resulting JSON as every operation's `default` response. Routes use Hummingbird's
  `BasicRequestContext`.
- `register(on:)` throws on duplicate routes and on two different types sharing a schema name.
  `register(on:docs: false)` registers the routes without `/openapi.json` and `/docs`.

## Options

- `maxBodySize:` on `@POST`/`@PUT`/`@PATCH` replaces the 2 MB body size limit for `body`/`form` (a `ByteCount`:
  `"512kb"`, `"10mb"`, units up to `gb` in powers of 1024); larger bodies get 413.
- `head: true` on `@GET` makes the route answer `HEAD` too, with the same status and headers and no body:
  `@GET(router, "/ping", head: true)` for a health check that monitors probe with `HEAD`. The OpenAPI document lists
  the `GET` only.

## Uploads

`UploadedFile` is a multipart file part, documented as a binary string. It's only coded through multipart; JSON
coders throw. A form field without a filename in its place is a 400.

Multipart parsing uses `multipart-kit`, pinned to `5.0.0-beta.2` because `5.0.0-beta.3` changed the part protocols
`UploadedFile` implements. An app that depends on `multipart-kit` itself has to accept that version.
