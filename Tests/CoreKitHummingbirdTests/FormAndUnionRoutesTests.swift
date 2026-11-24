import CoreKit
import CoreKitHummingbird
import Foundation
import Hummingbird
import HummingbirdTesting
import MultipartKit
import Testing

extension OpenAPITag {
    static let drawings = OpenAPITag("Drawings")
}

@Schema
struct UploadDrawingForm: Codable, Sendable {
    /// An SVG export.
    let file: UploadedFile
}

@Schema
struct UploadedDrawing: Codable, Sendable {
    let filename: String
    let contentType: String?
    let sizeBytes: Int
}

@Schema
struct Drawing: Codable, Sendable {
    let shapes: [Shape]
    let label: Label

    @Schema(tag: "kind")
    enum Shape: Codable, Sendable {
        case circle(Circle)
        case regularPolygon(RegularPolygon)
    }

    @Schema
    enum Label: Codable, Sendable {
        case text(String)
        case lines([String])
    }

    @Schema
    struct Circle: Codable, Sendable {
        let radius: Double
        let style: Style

        @Schema
        struct Style: Codable, Sendable {
            let color: String
        }
    }

    @Schema
    struct RegularPolygon: Codable, Sendable {
        let sides: Int
        let style: Style

        @Schema
        struct Style: Codable, Sendable {
            let filled: Bool
        }
    }
}

let drawingRouter = APIRouter("/drawings", tag: .drawings)

@POST(drawingRouter, "/")
func createDrawing(body: Drawing) async throws -> Drawing { body }

@POST(drawingRouter, "/upload", maxBodySize: "3mb")
func uploadDrawing(form: UploadDrawingForm) async throws -> UploadedDrawing {
    UploadedDrawing(filename: form.file.filename, contentType: form.file.contentType, sizeBytes: form.file.data.count)
}

@Test func formsAndUnionsServeRequestsAndDocumentThemselves() async throws {
    let router = Router()
    try OpenAPIDocument(title: "Test", version: "1.0.0", routers: testRouters).register(on: router)

    // A live server, so body size limits apply as in production.
    try await Application(router: router).test(.live) { client in
        // Larger than Hummingbird's 2mb default, within the route's 3mb.
        let svg = UploadedFile(filename: "drawing.svg", contentType: "image/svg+xml", data: Data(repeating: 0x20, count: 2_500_000))
        let uploaded = try await client.execute(
            uri: "/drawings/upload", method: .post, headers: multipartHeaders, body: try multipartBody(UploadDrawingForm(file: svg)))
        #expect(uploaded.status == .ok)
        #expect(
            try json(uploaded.body) as? NSDictionary == [
                "filename": "drawing.svg", "content_type": "image/svg+xml", "size_bytes": 2_500_000,
            ])
        let tooLarge = UploadedFile(filename: "large.svg", contentType: nil, data: Data(count: 4_000_000))
        let rejected = try await client.execute(
            uri: "/drawings/upload", method: .post, headers: multipartHeaders, body: try multipartBody(UploadDrawingForm(file: tooLarge)))
        #expect(rejected.status == .contentTooLarge)
        let notMultipart = try await client.execute(
            uri: "/drawings/upload", method: .post, headers: [.contentType: "application/json"],
            body: ByteBuffer(string: #"{"file":"drawing.svg"}"#))
        #expect(notMultipart.status == .unsupportedMediaType)

        let drawing = """
            {"shapes":[{"kind":"circle","radius":1,"style":{"color":"red"}},\
            {"kind":"regular_polygon","sides":6,"style":{"filled":true}}],"label":["a","b"]}
            """
        let created = try await client.execute(
            uri: "/drawings", method: .post, headers: [.contentType: "application/json"], body: ByteBuffer(string: drawing))
        #expect(try json(created.body) as? NSDictionary == json(ByteBuffer(string: drawing)) as? NSDictionary)

        let document = try #require(try await json(client.execute(uri: "/openapi.json", method: .get).body) as? [String: Any])
        let upload: [String: Any]? = value(document, "paths", "/drawings/upload", "post", "requestBody", "content")
        #expect(upload?.keys.sorted() == ["multipart/form-data"])
        let schemas = try #require(value(document, "components", "schemas") as [String: Any]?)
        #expect(
            Set(schemas.keys).isSuperset(of: [
                "Drawing", "Drawing.Circle.Style", "Drawing.Label", "Drawing.RegularPolygon.Style", "Drawing.Shape",
                "UploadDrawingForm", "UploadedDrawing",
            ]))
        #expect(
            value(schemas, "UploadDrawingForm", "properties", "file") as NSDictionary? == [
                "type": "string", "format": "binary", "description": "An SVG export.",
            ])
        let circle = try #require((value(schemas, "Drawing.Shape", "anyOf") as [NSDictionary]?)?.first)
        #expect(
            circle == [
                "type": "object",
                "properties": [
                    "kind": ["type": "string", "enum": ["circle"]],
                    "radius": ["type": "number", "format": "double"],
                    "style": ["$ref": "#/components/schemas/Drawing.Circle.Style"],
                ],
                "required": ["kind", "radius", "style"],
            ])
    }
}

private let multipartHeaders: HTTPFields = [.contentType: "multipart/form-data; boundary=corekit-test"]

private func multipartBody(_ form: some Encodable) throws -> ByteBuffer {
    ByteBuffer(bytes: try FormDataEncoder().encode(form, boundary: "corekit-test", to: Data.self))
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
