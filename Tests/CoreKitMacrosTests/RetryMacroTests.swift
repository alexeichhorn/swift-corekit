import CoreKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros = [
    "Retry": MacroSpec(type: RetryMacro.self),
    "Timeout": MacroSpec(type: TimeoutMacro.self),
]

@Test func retryAndTimeoutWrapTheBody() {
    assertExpansion(
        """
        @Retry(maxRetries: 1, initialDelay: .seconds(1), jitter: false, timeout: .seconds(120))
        func sendReport(_ request: Report) async throws -> Response {
            let data = try await send(request)
            return try decode(data)
        }

        @Timeout(.seconds(30))
        func fetchPage(_ url: URL) async throws -> Page { try await load(url) }
        """,
        expandedSource: """
            func sendReport(_ request: Report) async throws -> Response {
                return try await CoreKit.retry(maxRetries: 1, initialDelay: .seconds(1), jitter: false, timeout: .seconds(120)) {
                    let data = try await send(request)
                    return try decode(data)
                }
            }
            func fetchPage(_ url: URL) async throws -> Page {
                return try await CoreKit.withTimeout(.seconds(30)) {
                    try await load(url)
                }
            }
            """,
        macros: macros
    )
}

@Test func retryAndTimeoutRejectOtherFunctionsAndEachOther() {
    assertExpansion(
        """
        @Retry(maxRetries: 4)
        func scale(_ inputs: [[Int]]) async -> [[Float]] { [] }

        @Timeout(.seconds(30))
        func fetchPage(_ url: URL) throws -> Page { try load(url) }

        @Retry(maxRetries: 4)
        @Timeout(.seconds(30))
        func sendReport() async throws {}
        """,
        expandedSource: """
            func scale(_ inputs: [[Int]]) async -> [[Float]] { [] }
            func fetchPage(_ url: URL) throws -> Page { try load(url) }
            func sendReport() async throws {}
            """,
        diagnostics: [
            DiagnosticSpec(message: "@Retry requires an 'async throws' function", line: 1, column: 1),
            DiagnosticSpec(message: "@Timeout requires an 'async throws' function", line: 4, column: 1),
            DiagnosticSpec(
                message: "@Retry and @Timeout can't be combined on one function; write @Retry(..., timeout: ...) instead", line: 7,
                column: 1),
            DiagnosticSpec(
                message: "@Retry and @Timeout can't be combined on one function; write @Retry(..., timeout: ...) instead", line: 8,
                column: 1),
        ],
        macros: macros
    )
}
