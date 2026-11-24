import CoreKit
import CoreKitHummingbird
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

/// Has no tag of its own, so its operations take the including router's.
let orderNoteRouter = APIRouter("/notes")

@GET(orderNoteRouter, "/:orderID")
func listOrderNotes(orderID: Int64) async throws -> [String] { ["note for \(orderID)"] }

@GET(orderRouter, "/by-reference/:reference")
func findOrder(reference: UUID) async throws -> OrderResponse {
    OrderResponse(id: 1, ownerID: reference.uuidString, title: "found", dueAt: nil)
}

@POST(orderRouter, "/drafts")
func createDraftOrder(body: CreateOrderInput) async throws -> Response {
    try Response(status: .created, json: OrderResponse(id: 2, ownerID: "draft", title: body.title, dueAt: body.dueAt))
}

@Test func routesBindUUIDsAndAnswerWithTheirOwnStatus() async throws {
    let router = Router()
    try OpenAPIDocument(title: "Test & Co", version: "1.0.0", routers: testRouters).register(on: router)

    try await Application(router: router).test(.router) { client in
        let found = try await client.execute(uri: "/orders/by-reference/E621E1F8-C36C-495A-93FC-0C247A3E6E5F", method: .get)
        #expect(
            String(buffer: found.body)
                == #"{"id":1,"owner_id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"found","due_at":null}"#)
        #expect(try await client.execute(uri: "/orders/by-reference/not-a-uuid", method: .get).status == .badRequest)

        let draft = try await client.execute(
            uri: "/orders/drafts", method: .post, body: ByteBuffer(string: #"{"title":"Gift","due_at":"2026-01-02T03:04:05Z"}"#))
        #expect(draft.status == .created)
        #expect(draft.headers[.contentType] == "application/json; charset=utf-8")
        #expect(String(buffer: draft.body) == #"{"id":2,"owner_id":"draft","title":"Gift","due_at":"2026-01-02T03:04:05Z"}"#)

        #expect(String(buffer: try await client.execute(uri: "/orders/notes/7", method: .get).body) == #"["note for 7"]"#)

        let docs = try await client.execute(uri: "/docs", method: .get)
        #expect(docs.headers[.contentType] == "text/html; charset=utf-8")
        #expect(String(buffer: docs.body).contains("<title>Test &amp; Co</title>"))
        #expect(String(buffer: docs.body).contains(#"url: "/openapi.json""#))

        let document = try #require(
            try JSONSerialization.jsonObject(
                with: Data(try await client.execute(uri: "/openapi.json", method: .get).body.readableBytesView))
                as? [String: Any])
        let paths = try #require(document["paths"] as? [String: [String: [String: Any]]])
        #expect(paths["/orders/notes/{orderID}"]?["get"]?["tags"] as? [String] == ["Orders"])
        #expect(
            paths["/orders/by-reference/{reference}"]?["get"]?["parameters"] as? [NSDictionary] == [
                ["name": "reference", "in": "path", "required": true, "schema": ["type": "string", "format": "uuid"]]
            ])
        // A handler-built response is documented without a schema.
        #expect(paths["/orders/drafts"]?["post"]?["responses"] as? NSDictionary == ["200": ["description": "Successful Response"]])
    }
}

@Test func registerWithoutDocsLeavesOutTheDocument() async throws {
    let router = Router()
    try OpenAPIDocument(title: "Test", version: "1.0.0", routers: testRouters).register(on: router, docs: false)

    try await Application(router: router).test(.router) { client in
        let notes = try await client.execute(uri: "/orders/notes/7", method: .get)
        let document = try await client.execute(uri: "/openapi.json", method: .get)
        let docs = try await client.execute(uri: "/docs", method: .get)
        #expect(notes.status == .ok)
        #expect(document.status == .notFound)
        #expect(docs.status == .notFound)
    }
}

@Test func aRouterIncludedTwiceIsRejected() {
    #expect(throws: (any Error).self) {
        try OpenAPIDocument(title: "Test", version: "1.0.0", routers: testRouters + [orderActivityRouter])
    }
}

/// Dates in UTC with `Z` and a fraction only when they have one, lowercase UUIDs, and `null` for an unset property.
@Test func responseEncoderWritesWhatSerdeAndPydanticWrite() throws {
    struct Stamp: Encodable {
        let at: Date
        let whole: Date
        let id: UUID
        let note: String?
    }
    let stamp = Stamp(
        at: Date(timeIntervalSince1970: 1_767_323_045.123),
        whole: Date(timeIntervalSince1970: 1_767_323_045),
        id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        note: nil
    )
    #expect(
        String(decoding: try RouteBinding.responseEncoder.encode(stamp), as: UTF8.self)
            == #"{"at":"2026-01-02T03:04:05.123Z","whole":"2026-01-02T03:04:05Z","id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","note":null}"#
    )
}

@Test func byteCountsReadTheirUnits() {
    let sizes: [ByteCount] = ["512kb", "10MB", "1gb", "300b", "42", 7]
    #expect(sizes.map(\.bytes) == [524_288, 10_485_760, 1_073_741_824, 300, 42, 7])
}

@Test func uploadedFilesAreCodedOnlyAsMultipartParts() {
    let file = UploadedFile(filename: "receipt.txt", contentType: "text/plain", data: Data("hi".utf8))
    #expect(throws: EncodingError.self) { try JSONEncoder().encode(file) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(UploadedFile.self, from: Data(#""receipt.txt""#.utf8)) }
}

/// A part without a filename is a plain form field, not a file.
@Test func aFormFieldInPlaceOfAFileIsAClientError() async throws {
    let router = Router()
    try OpenAPIDocument(title: "Test", version: "1.0.0", routers: testRouters).register(on: router)

    try await Application(router: router).test(.router) { client in
        let body = "--corekit-test\r\nContent-Disposition: form-data; name=\"file\"\r\n\r\nhello\r\n--corekit-test--\r\n"
        let response = try await client.execute(
            uri: "/drawings/upload", method: .post, headers: [.contentType: "multipart/form-data; boundary=corekit-test"],
            body: ByteBuffer(string: body))
        #expect(response.status == .badRequest)
    }
}
