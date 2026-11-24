import AsyncHTTPClient
import Foundation
import NIOCore
import NIOPosix

#if canImport(Network)
    import Network
#endif

extension HTTPClient {
    /// A shared client that adds nothing of its own to a request: no timeout unless the request sets one, and a
    /// refused connection is an error at once. It follows at most 10 redirects, speaks HTTP/1.1 and opens a connection
    /// for every request a host is sent at once, up to 1024.
    ///
    /// `HTTPClient.shared` is set up like a browser instead: it retries a refused connection for 90 seconds and ends a
    /// request after 90 seconds without data, whatever timeout the request has.
    ///
    /// It lives as long as the process, so nothing shuts it down.
    public static let plain = plain(connectTimeout: nil)

    /// A new client like ``plain`` that gives up connecting after `connectTimeout`, with
    /// `HTTPClientError.connectTimeout`. Create it once and keep it: nothing shuts it down.
    public static func plain(connectTimeout: Duration?) -> HTTPClient {
        var configuration = HTTPClient.Configuration()
        // Without a connect timeout AsyncHTTPClient applies 10 seconds. The default here never fires, so connecting
        // ends when the operating system gives up.
        let connect = connectTimeout.map(TimeAmount.init) ?? .nanoseconds(.max)
        configuration.timeout = HTTPClient.Configuration.Timeout(connect: connect, read: nil)
        configuration.connectionPool.retryConnectionEstablishment = false
        // AsyncHTTPClient's default of 8 queues every further request to a host, and a queued one fails once it has
        // waited as long as the connect timeout.
        configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = 1024
        // On Apple platforms a refused connection otherwise waits for the network to change, until the timeout.
        configuration.networkFrameworkWaitForConnectivity = false
        configuration.redirectConfiguration = .follow(max: 10, allowCycles: false)
        configuration.httpVersion = .http1Only
        return HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
    }

    /// Whether `error` means no connection to the server was made: it refused, or its name did not resolve. Such a
    /// request never arrived, so it is safe to send again.
    public static func isConnectionFailure(_ error: any Error) -> Bool {
        #if canImport(Network)
            if error is NWError { return true }
        #endif
        // A host given by name fails with `NIOConnectionError`, one given as an address with the plain system error.
        if let error = error as? IOError {
            return [ECONNREFUSED, EHOSTUNREACH, ENETUNREACH].contains(error.errnoCode)
        }
        return error is NIOConnectionError
    }

    /// Sends `request` and returns the response once it has started.
    ///
    /// `timeout` limits the whole exchange, from connecting until the body has been read. A request or a body that
    /// takes longer fails with `HTTPClientError.deadlineExceeded`. Without one the request waits as long as it takes.
    ///
    /// A header value with a control character, such as a line break, fails with ``InvalidHeaderValueError``.
    public func send(_ request: HTTPClientRequest, timeout: Duration? = nil) async throws -> HTTPClientResponse {
        // AsyncHTTPClient refuses such a value too, but quotes it in its error, and it may be a credential.
        let isControlCharacter = { (byte: UInt8) in (byte < 0x20 && byte != UInt8(ascii: "\t")) || byte == 0x7F }
        if let header = request.headers.first(where: { $0.value.utf8.contains(where: isControlCharacter) }) {
            throw InvalidHeaderValueError(header: header.name)
        }
        guard let timeout else {
            return try await execute(request, deadline: .distantFuture)
        }
        let deadline = ContinuousClock.now + timeout
        var response = try await execute(request, deadline: .now() + TimeAmount(timeout))
        // AsyncHTTPClient's own deadline ends when the response starts, so the body gets the rest of the time here.
        response.body = .stream(DeadlineBody(body: response.body, deadline: deadline))
        return response
    }

    /// Whether `error` means the request ran into the `timeout` given to ``send(_:timeout:)``.
    public static func isTimeout(_ error: any Error) -> Bool {
        (error as? HTTPClientError) == .deadlineExceeded
    }
}

/// Thrown by ``AsyncHTTPClient/HTTPClient/send(_:timeout:)``. It names the header and leaves out its value.
public struct InvalidHeaderValueError: Error, CustomStringConvertible {
    public let header: String

    public var description: String { "the value of the \(header) header contains a control character" }
}

/// A response body whose every read fails once `deadline` has passed.
private struct DeadlineBody: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    let body: HTTPClientResponse.Body
    let deadline: ContinuousClock.Instant

    func makeAsyncIterator() -> Iterator {
        Iterator(reader: Reader(iterator: body.makeAsyncIterator()), deadline: deadline)
    }

    struct Iterator: AsyncIteratorProtocol {
        let reader: Reader
        let deadline: ContinuousClock.Instant

        func next() async throws -> ByteBuffer? {
            try await withThrowingTaskGroup(of: ByteBuffer?.self) { group in
                defer { group.cancelAll() }
                group.addTask { [reader] in try await reader.next() }
                group.addTask { [deadline] in
                    try await ContinuousClock().sleep(until: deadline)
                    throw HTTPClientError.deadlineExceeded
                }
                return try await group.next()!
            }
        }
    }

    /// Carries the body's iterator into the task that reads the next chunk. Only one chunk is read at a time.
    final class Reader: @unchecked Sendable {
        private var iterator: HTTPClientResponse.Body.AsyncIterator

        init(iterator: HTTPClientResponse.Body.AsyncIterator) {
            self.iterator = iterator
        }

        func next() async throws -> ByteBuffer? {
            try await iterator.next()
        }
    }
}

extension HTTPClientRequest {
    /// Sets `Authorization: Bearer <token>`.
    public mutating func setBearerAuth(_ token: String) {
        headers.replaceOrAdd(name: "Authorization", value: "Bearer \(token)")
    }

    /// Appends `parameters` to the URL's query as form fields, in the given order: a space becomes `+`, and every
    /// byte other than an ASCII letter, a digit or one of `*-._` becomes `%XX`. A fragment stays at the end.
    public mutating func addQuery(_ parameters: [(name: String, value: String)]) {
        if parameters.isEmpty { return }
        let fields = parameters.map { "\(Self.formEncoded($0.name))=\(Self.formEncoded($0.value))" }.joined(separator: "&")
        let queryEnd = url.firstIndex(of: "#") ?? url.endIndex
        url.insert(contentsOf: (url[..<queryEnd].contains("?") ? "&" : "?") + fields, at: queryEnd)
    }

    private static func formEncoded(_ text: String) -> String {
        let digits = Array("0123456789ABCDEF".utf8)
        var encoded: [UInt8] = []
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
                encoded.append(byte)
            case UInt8(ascii: " "):
                encoded.append(UInt8(ascii: "+"))
            default:
                encoded += [UInt8(ascii: "%"), digits[Int(byte >> 4)], digits[Int(byte & 0x0f)]]
            }
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// Sets the body to `value` as JSON, with `Content-Type: application/json`. `JSONEncoder` writes it, unless
    /// `encode` is another encoder's method: `setJSONBody(event, encode: OrderedJSONEncoder().encode)`.
    public mutating func setJSONBody<Value: Encodable>(
        _ value: Value,
        encode: (Value) throws -> Data = { try JSONEncoder().encode($0) }
    ) throws {
        headers.replaceOrAdd(name: "Content-Type", value: "application/json")
        body = .bytes(ByteBuffer(bytes: try encode(value)))
    }
}

extension HTTPClientResponse {
    /// Reads the whole body.
    public func data() async throws -> Data {
        Data(try await body.collect(upTo: .max).readableBytesView)
    }

    /// Reads the whole body as text. Bytes that are not valid UTF-8 become `�`.
    public func text() async throws -> String {
        String(buffer: try await body.collect(upTo: .max))
    }
}
