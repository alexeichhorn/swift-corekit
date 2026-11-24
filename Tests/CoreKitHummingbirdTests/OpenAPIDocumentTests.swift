import CoreKit
import CoreKitHummingbird
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

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

    static var openAPISecurity: OpenAPISecurityScheme? { .bearer(format: "demo-user-id") }
}

@Schema
struct CreateOrderInput: Codable, Sendable {
    /// Shown on the receipt.
    let title: String
    let dueAt: Date?
}

@Schema
struct ListOrdersQuery: Codable, Sendable {
    /// Page size.
    @Range(1...100) let limit: Int
    let includeDone: Bool?
}

@Schema
struct OrderResponse: Codable, Sendable {
    let id: Int64
    let ownerID: String
    let title: String
    let dueAt: Date?
}

@Schema
struct ErrorResponse: Codable, Sendable {
    let message: String
}

let orderActivityRouter = APIRouter("/activity", tag: .orderActivity)
let orderRouter = APIRouter("/orders", tag: .orders, include: [orderActivityRouter, orderNoteRouter])

/// Creates a order.
@POST(orderRouter, "/")
func createOrder(user: AuthUser, body: CreateOrderInput) async throws -> OrderResponse {
    OrderResponse(id: 1, ownerID: user.id, title: body.title, dueAt: body.dueAt)
}

@GET(orderRouter, "/", head: true)
func listOrders(user: AuthUser, query: ListOrdersQuery) async throws -> [OrderResponse] {
    (0..<query.limit).map { OrderResponse(id: Int64($0), ownerID: user.id, title: "\(query.includeDone ?? false)", dueAt: nil) }
}

@DELETE(orderRouter, "/:orderID")
func deleteOrder(user: AuthUser, orderID: Int64) async throws {}

@GET(orderActivityRouter, "/:orderID")
func latestOrderActivity(orderID: Int64) async throws -> OrderResponse? { nil }

/// Every router of the test binary: discovery finds all routes in the process, so each document includes them all.
let testRouters = [orderRouter, drawingRouter]

@Test func registeredRoutesServeRequestsAndDocumentThemselves() async throws {
    #expect(throws: (any Error).self, "a handler on a router that isn't included") {
        try OpenAPIDocument(title: "Test", version: "1.0.0", routers: [orderRouter])
    }

    let router = Router()
    try OpenAPIDocument(title: "Test", version: "1.0.0", errorResponse: ErrorResponse.self, routers: testRouters).register(on: router)

    try await Application(router: router).test(.router) { client in
        let created = try await client.execute(
            uri: "/orders", method: .post, headers: [.authorization: "Bearer user-1"],
            body: ByteBuffer(string: #"{"title":"Gift wrap","due_at":"2026-01-02T03:04:05Z"}"#))
        #expect(created.status == .ok)
        #expect(
            try json(created.body) as? NSDictionary == [
                "id": 1, "owner_id": "user-1", "title": "Gift wrap", "due_at": "2026-01-02T03:04:05Z",
            ])

        let listed = try await client.execute(
            uri: "/orders?limit=2&include_done=true", method: .get, headers: [.authorization: "Bearer user-1"])
        #expect((try json(listed.body) as? [[String: Any]])?.map { $0["title"] as? String } == ["true", "true"])
        // An unset property is written as `null`, and the keys keep their declaration order.
        let one = try await client.execute(uri: "/orders?limit=1", method: .get, headers: [.authorization: "Bearer user-1"])
        #expect(String(buffer: one.body) == #"[{"id":0,"owner_id":"user-1","title":"false","due_at":null}]"#)

        // `head: true` answers HEAD like the GET, without the body; a route without it does not answer HEAD.
        let head = try await client.execute(
            uri: "/orders?limit=2&include_done=true", method: .head, headers: [.authorization: "Bearer user-1"])
        #expect(head.status == .ok && head.body.readableBytes == 0)
        #expect(try await client.execute(uri: "/orders/activity/7", method: .head).status == .notFound)

        #expect(
            try await client.execute(uri: "/orders/7", method: .delete, headers: [.authorization: "Bearer user-1"]).status == .noContent)
        #expect(
            try await client.execute(uri: "/orders/seven", method: .delete, headers: [.authorization: "Bearer user-1"]).status
                == .badRequest
        )
        #expect(try await client.execute(uri: "/orders/7", method: .delete).status == .unauthorized)
        // A parameter given twice is the client's mistake, not a server error.
        #expect(
            try await client.execute(uri: "/orders?limit=1&limit=2", method: .get, headers: [.authorization: "Bearer user-1"]).status
                == .badRequest)
        let malformed = try await client.execute(
            uri: "/orders", method: .post, headers: [.authorization: "Bearer user-1"], body: ByteBuffer(string: #"{"title":"#))
        #expect(malformed.status == .badRequest)
        #expect(String(buffer: try await client.execute(uri: "/orders/activity/7", method: .get).body) == "null")

        let document = try #require(try await json(client.execute(uri: "/openapi.json", method: .get).body) as? [String: Any])
        let paths = try #require(document["paths"] as? [String: [String: [String: Any]]])
        #expect(Set(paths.keys).isSuperset(of: ["/orders", "/orders/{orderID}", "/orders/activity/{orderID}"]))

        let create = try #require(paths["/orders"]?["post"])
        #expect(create["operationId"] as? String == "create_order")
        #expect(create["summary"] as? String == "Creates a order.")
        #expect(create["tags"] as? [String] == ["Orders"])
        #expect(create["security"] as? [[String: [String]]] == [["BearerAuth": []]])
        #expect(value(create, "requestBody", "content", "application/json", "schema", "$ref") == "#/components/schemas/CreateOrderInput")
        #expect(
            value(create, "responses", "200", "content", "application/json", "schema", "$ref") == "#/components/schemas/OrderResponse")
        #expect(
            value(create, "responses", "default", "content", "application/json", "schema", "$ref")
                == "#/components/schemas/ErrorResponse")

        let listParameters = try #require(paths["/orders"]?["get"]?["parameters"] as? [NSDictionary])
        #expect(
            listParameters == [
                [
                    "name": "limit", "in": "query", "required": true, "description": "Page size.",
                    "schema": ["type": "integer", "format": "int64", "minimum": 1, "maximum": 100],
                ],
                ["name": "include_done", "in": "query", "required": false, "schema": ["type": "boolean"]],
            ]
        )

        let delete = try #require(paths["/orders/{orderID}"]?["delete"])
        #expect(
            delete["parameters"] as? [NSDictionary] == [
                ["name": "orderID", "in": "path", "required": true, "schema": ["type": "integer", "format": "int64"]]
            ])
        #expect(value(delete, "responses", "204", "description") == "No Content")

        let latest = try #require(paths["/orders/activity/{orderID}"]?["get"])
        #expect(latest["tags"] as? [String] == ["Order Activity"])
        #expect(latest["security"] == nil)

        let createInput = value(document, "components", "schemas", "CreateOrderInput") as NSDictionary?
        #expect(
            createInput == [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Shown on the receipt."],
                    "due_at": ["type": ["string", "null"], "format": "date-time"],
                ],
                "required": ["title"],
            ]
        )
        #expect(
            value(document, "components", "securitySchemes", "BearerAuth") as NSDictionary? == [
                "type": "http", "scheme": "bearer", "bearerFormat": "demo-user-id",
            ])
        #expect((document["tags"] as? [[String: String]])?.map { $0["name"] } == ["Orders", "Order Activity", "Drawings"])
    }
}

private func json(_ body: ByteBuffer) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(body.readableBytesView), options: .fragmentsAllowed)
}

/// The value at a key path through nested JSON objects.
private func value<Value>(_ object: [String: Any], _ keys: String...) -> Value? {
    var current: Any? = object
    for key in keys { current = (current as? [String: Any])?[key] }
    return current as? Value
}
