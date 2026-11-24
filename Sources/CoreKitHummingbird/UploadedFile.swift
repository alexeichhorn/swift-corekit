public import CoreKit
public import Foundation
import Hummingbird
public import MultipartKit

/// A file part of a `multipart/form-data` body. Use it as a property of a handler's `form:` type:
///
/// ```swift
/// @Schema
/// struct UploadReceiptForm: Codable, Sendable {
///     /// The receipt as PDF.
///     let file: UploadedFile
/// }
/// ```
///
/// It's coded only as a multipart part; other coders throw.
public struct UploadedFile: Sendable, SchemaRepresentable {
    public let filename: String
    /// The part's `Content-Type`, as sent by the client.
    public let contentType: String?
    public let data: Data

    public init(filename: String, contentType: String?, data: Data) {
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }

    /// Swagger UI shows a file picker for binary strings in a multipart body.
    public static var jsonSchema: JSONSchema { .string(format: "binary") }
}

extension UploadedFile: MultipartPartConvertible {
    public var multipart: MultipartPart<Data> {
        var headerFields: HTTPFields = [.contentDisposition: "form-data; filename=\"\(filename)\""]
        headerFields[.contentType] = contentType
        return MultipartPart(headerFields: headerFields, body: data)
    }

    /// A part without a filename is a plain form field, not a file (400).
    public init(multipart: MultipartPart<Data>) throws {
        guard let filename = try multipart.contentDisposition?.filename else {
            throw HTTPError(.badRequest, message: "Expected a file, got a form field")
        }
        self.init(filename: filename, contentType: multipart.headerFields[.contentType], data: multipart.body)
    }
}

/// Lets forms holding an `UploadedFile` be `Codable`; `FormDataDecoder`/`FormDataEncoder` use the multipart part instead.
extension UploadedFile: Codable {
    public init(from decoder: any Decoder) throws {
        throw DecodingError.typeMismatch(
            Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected a multipart/form-data file part"))
    }

    public func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(
            self, .init(codingPath: encoder.codingPath, debugDescription: "UploadedFile is only encoded as a multipart/form-data part"))
    }
}
