import CoreKit
import Testing

@Test func contextErrorsDescribeTheWholeChain() async throws {
    struct Refused: Error, CustomStringConvertible { var description: String { "connection refused" } }
    let error = await #expect(throws: ContextError.self) {
        try await withContext("failed to load orders") {
            try await withContext("db query error") { throw Refused() }
        }
    }
    #expect(error?.description == "failed to load orders: db query error: connection refused")
    #expect(ContextError("no scopes").description == "no scopes")
}

@Test func withContextReturnsTheResultOfItsOperation() async throws {
    #expect(try await withContext("failed to count orders") { 3 } == 3)
}

/// Some errors keep their details out of the plain description and show them only in the debug description.
@Test func errorDescriptionPrefersTheDebugDescription() {
    struct QueryFailed: Error, CustomStringConvertible, CustomDebugStringConvertible {
        var description: String { "query failed" }
        var debugDescription: String { "query failed: relation \"orders\" does not exist" }
    }
    #expect(errorDescription(QueryFailed()) == "query failed: relation \"orders\" does not exist")
    #expect(
        ContextError("failed to load orders", cause: QueryFailed()).description
            == "failed to load orders: query failed: relation \"orders\" does not exist")
}
