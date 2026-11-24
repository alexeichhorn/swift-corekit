public import CoreKit
public import Foundation
public import Hummingbird
import MultipartKit

/// Request decoding and response encoding used by the route macro expansions.
///
/// Everything is `async throws` so generated handlers can always be written as `try await`.
public enum RouteBinding {
    /// An unparsable value is a client error (400).
    public static func pathParameter<Value: LosslessStringConvertible>(
        _ name: String,
        as type: Value.Type,
        in request: Request,
        context: BasicRequestContext
    ) async throws -> Value {
        try parsePathParameter(name, context: context, Value.init)
    }

    public static func pathParameter(_ name: String, as type: UUID.Type, in request: Request, context: BasicRequestContext) async throws
        -> UUID
    {
        try parsePathParameter(name, context: context, UUID.init(uuidString:))
    }

    private static func parsePathParameter<Value>(_ name: String, context: BasicRequestContext, _ parse: (String) -> Value?) throws -> Value
    {
        guard let rawValue = context.parameters.get(name) else {
            throw HTTPError(.internalServerError, message: "Path parameter '\(name)' isn't part of the route")
        }
        guard let value = parse(rawValue) else {
            throw HTTPError(.badRequest, message: "Invalid path parameter '\(name)': \(rawValue)")
        }
        return value
    }

    /// A query that does not decode is a client error (400), also when it is malformed or repeats a parameter.
    public static func query<Value: Decodable>(_ type: Value.Type, in request: Request, context: BasicRequestContext) async throws -> Value
    {
        do {
            return try request.uri.decodeQuery(as: Value.self, context: context)
        } catch let error as any HTTPResponseError {
            throw error
        } catch {
            throw HTTPError(.badRequest, message: "Invalid query: \(error)")
        }
    }

    /// Decodes JSON regardless of the `Content-Type` header, matching the documented `application/json` body. A body
    /// that does not decode is rejected with `InvalidRequestBodyError`, a 400.
    ///
    /// - Parameter maxBodySize: `nil` uses the context's limit; a larger body is rejected with 413.
    public static func body<Value: Decodable>(
        _ type: Value.Type,
        in request: Request,
        context: BasicRequestContext,
        maxBodySize: ByteCount? = nil
    ) async throws -> Value {
        let body = try await request.body.collect(upTo: maxBodySize?.bytes ?? context.maxUploadSize)
        do {
            return try jsonDecoder.decode(Value.self, from: Data(body.readableBytesView))
        } catch let error as DecodingError {
            throw InvalidRequestBodyError(error)
        }
    }

    /// A request that isn't `multipart/form-data` is rejected with 415, a malformed one with 400.
    ///
    /// - Parameter maxBodySize: `nil` uses the context's limit; a larger body is rejected with 413.
    public static func form<Value: Decodable>(
        _ type: Value.Type,
        in request: Request,
        context: BasicRequestContext,
        maxBodySize: ByteCount? = nil
    ) async throws -> Value {
        guard let mediaType = request.headers[.contentType].flatMap(MediaType.init(from:)), mediaType.isType(.multipartForm),
            let boundary = mediaType.parameter.flatMap({ $0.name.lowercased() == "boundary" ? $0.value : nil })
        else {
            throw HTTPError(.unsupportedMediaType, message: "Expected a multipart/form-data body")
        }
        let body = try await request.body.collect(upTo: maxBodySize?.bytes ?? context.maxUploadSize)
        do {
            return try FormDataDecoder().decode(Value.self, from: Data(body.readableBytesView), boundary: boundary)
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError(.badRequest, message: "Invalid multipart/form-data body: \(error)")
        }
    }

    /// Writes a response as serde and pydantic do: an unset property as `null`, keys in declaration order, lowercase
    /// UUIDs, and dates in UTC with `Z` and a fraction only when they have one (`2026-01-02T03:04:05.123Z`).
    public static let responseEncoder = OrderedJSONEncoder(
        dateEncoding: .custom { .string("\($0.rfc3339.dropLast("+00:00".count))Z") }, lowercaseUUIDs: true)

    public static func json<Value: Encodable>(_ value: Value, for request: Request, context: BasicRequestContext) async throws -> Response {
        try Response(status: .ok, json: value)
    }

    public static func noContent(_ result: Void, for request: Request, context: BasicRequestContext) async throws -> Response {
        Response(status: .noContent)
    }

    public static func raw(_ response: Response, for request: Request, context: BasicRequestContext) async throws -> Response {
        response
    }

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Response {
    /// A JSON response with a status of its own, written as a handler's returned value is. Its body is not documented.
    public init(status: HTTPResponse.Status, json value: some Encodable) throws {
        self.init(
            status: status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(bytes: try RouteBinding.responseEncoder.encode(value)))
        )
    }
}

/// A JSON request body that did not decode: malformed JSON, a missing property or a value of the wrong type.
///
/// Answered with 400. An app that answers errors in its own form catches it and reads `error`.
public struct InvalidRequestBodyError: HTTPResponseError {
    public let error: DecodingError

    public init(_ error: DecodingError) {
        self.error = error
    }

    public var status: HTTPResponse.Status { .badRequest }

    public func response(from request: Request, context: some RequestContext) throws -> Response {
        try HTTPError(.badRequest, message: "Invalid JSON body: \(error)").response(from: request, context: context)
    }
}
