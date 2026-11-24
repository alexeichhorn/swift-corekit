import AsyncHTTPClient
import CoreKitHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Synchronization
import Testing

/// Answers a request with the response head and half of the body it announced, then stays silent.
private final class StallingServer: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private var answered = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !answered else { return }
        answered = true
        var response = context.channel.allocator.buffer(capacity: 64)
        response.writeString("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhalf")
        context.writeAndFlush(NIOAny(response), promise: nil)
    }
}

@Test func timeoutCoversTheBody() async throws {
    let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .childChannelInitializer { channel in
            channel.eventLoop.makeCompletedFuture { try channel.pipeline.syncOperations.addHandler(StallingServer()) }
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()
    defer { server.close(promise: nil) }
    let port = try #require(server.localAddress?.port)

    // The response starts in time, so `send` returns; the rest of the body never comes.
    let started = ContinuousClock.now
    let response = try await HTTPClient.plain.send(HTTPClientRequest(url: "http://127.0.0.1:\(port)/"), timeout: .milliseconds(500))
    #expect(response.status == .ok)
    let error = await #expect(throws: (any Error).self) { try await response.data() }

    #expect(error.map(HTTPClient.isTimeout) == true)
    #expect(ContinuousClock.now - started < .seconds(5))
}

/// The connections whose request is waiting for an answer.
private final class WaitingRequests: Sendable {
    let channels = Mutex<[any Channel]>([])
}

/// Holds every request until `expected` of them are waiting, then answers them all.
private final class GatheringServer: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let waiting: WaitingRequests
    private let expected: Int

    init(waiting: WaitingRequests, expected: Int) {
        self.waiting = waiting
        self.expected = expected
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channel = context.channel
        let ready: [any Channel] = waiting.channels.withLock { channels in
            channels.append(channel)
            return channels.count == expected ? channels : []
        }
        for channel in ready {
            var response = channel.allocator.buffer(capacity: 64)
            response.writeString("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
            channel.writeAndFlush(response, promise: nil)
        }
    }
}

@Test func plainSendsManyRequestsToOneHostAtOnce() async throws {
    // More than the 8 connections AsyncHTTPClient opens to a host by default.
    let requests = 20
    let waiting = WaitingRequests()
    let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .childChannelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(GatheringServer(waiting: waiting, expected: requests))
            }
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()
    defer { server.close(promise: nil) }
    let port = try #require(server.localAddress?.port)

    // The server answers only once all of them have arrived, so a request that had to queue would end in the timeout.
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<requests {
            group.addTask {
                let response = try await HTTPClient.plain.send(HTTPClientRequest(url: "http://127.0.0.1:\(port)/"), timeout: .seconds(5))
                #expect(response.status == .ok)
            }
        }
        try await group.waitForAll()
    }
}

@Test func sendNamesAHeaderWithALineBreakWithoutQuotingItsValue() async throws {
    var request = HTTPClientRequest(url: "http://127.0.0.1:1/")
    request.headers.add(name: "Authorization", value: "Bearer first\nsecond")
    let error = try #require(await #expect(throws: InvalidHeaderValueError.self) { try await HTTPClient.plain.send(request) })
    #expect(error.header == "Authorization")
    #expect(!"\(error)".contains("second"))
}

@Test func addQueryFormEncodesAndAppends() {
    var request = HTTPClientRequest(url: "https://example.com/search")
    request.addQuery([])
    #expect(request.url == "https://example.com/search")

    request.addQuery([(name: "q", value: "Made Up Place, Mars"), (name: "city", value: "Zürich")])
    #expect(request.url == "https://example.com/search?q=Made+Up+Place%2C+Mars&city=Z%C3%BCrich")

    request.addQuery([(name: "a b", value: "*-._~+&=")])
    #expect(request.url.hasSuffix("&a+b=*-._%7E%2B%26%3D"))

    var withFragment = HTTPClientRequest(url: "https://example.com/search#results?")
    withFragment.addQuery([(name: "q", value: "x")])
    #expect(withFragment.url == "https://example.com/search?q=x#results?")
}

/// Answers every request with its body, and with its `Authorization` and `Content-Type` in `x-echo-` headers.
private final class EchoServer: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestHeaders = HTTPHeaders()
    private var body = ByteBuffer()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHeaders = head.headers
            body.clear()
        case .body(var chunk):
            body.writeBuffer(&chunk)
        case .end:
            var headers: HTTPHeaders = ["Content-Length": "\(body.readableBytes)"]
            for name in ["Authorization", "Content-Type"] {
                for value in requestHeaders[name] { headers.add(name: "x-echo-\(name.lowercased())", value: value) }
            }
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers))), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

private func startEchoServer() async throws -> any Channel {
    try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .childChannelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                try channel.pipeline.syncOperations.addHandler(EchoServer())
            }
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()
}

@Test func requestHelpersSetTheAuthorizationAndAJSONBody() async throws {
    struct OrderPatch: Encodable {
        let quantity: Int
    }
    let server = try await startEchoServer()
    defer { server.close(promise: nil) }
    let url = "http://127.0.0.1:\(try #require(server.localAddress?.port))/"

    var request = HTTPClientRequest(url: url)
    request.method = .POST
    request.setBearerAuth("first")
    request.setBearerAuth("second")
    try request.setJSONBody(OrderPatch(quantity: 3))
    let response = try await HTTPClient.plain.send(request, timeout: .seconds(5))

    #expect(response.headers["x-echo-authorization"] == ["Bearer second"])
    #expect(response.headers["x-echo-content-type"] == ["application/json"])
    #expect(try await response.text() == #"{"quantity":3}"#)

    // Another encoder's method writes the body instead of `JSONEncoder`.
    var raw = HTTPClientRequest(url: url)
    raw.method = .POST
    try raw.setJSONBody(OrderPatch(quantity: 3)) { _ in Data([0x61, 0xFF]) }
    #expect(try await HTTPClient.plain.send(raw, timeout: .seconds(5)).data() == Data([0x61, 0xFF]))
}

@Test func textReplacesInvalidUTF8() async throws {
    let server = try await startEchoServer()
    defer { server.close(promise: nil) }
    var request = HTTPClientRequest(url: "http://127.0.0.1:\(try #require(server.localAddress?.port))/")
    request.method = .POST
    request.body = .bytes(ByteBuffer(bytes: [0x61, 0xFF]))

    #expect(try await HTTPClient.plain.send(request, timeout: .seconds(5)).text() == "a\u{FFFD}")
}

/// A refused connection fails at once and counts as a connection failure; other failures don't.
@Test func refusedConnectionsAreConnectionFailures() async throws {
    let started = ContinuousClock.now
    let refused = await #expect(throws: (any Error).self) {
        try await HTTPClient.plain.send(HTTPClientRequest(url: "http://127.0.0.1:1/"))
    }
    #expect(refused.map(HTTPClient.isConnectionFailure) == true)
    #expect(ContinuousClock.now - started < .seconds(5))

    struct Unrelated: Error {}
    #expect(!HTTPClient.isConnectionFailure(Unrelated()))
    #expect(!HTTPClient.isConnectionFailure(HTTPClientError.deadlineExceeded))
}
