/// An error with a message and, optionally, the error that caused it. Its description is the whole chain, outermost
/// first: `failed to load orders: db query error: connection closed`.
public struct ContextError: Error, CustomStringConvertible {
    public let message: String
    public let cause: (any Error)?

    public init(_ message: String, cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }

    public var description: String {
        guard let cause else { return message }
        return "\(message): \(errorDescription(cause))"
    }
}

/// Runs `operation` and wraps an error it throws in a ``ContextError`` that says what was being done:
/// `try await withContext("failed to load orders") { try await repo.list() }`.
@discardableResult
nonisolated(nonsending) public func withContext<Value>(
    _ message: @autoclosure () -> String,
    operation: () async throws -> Value
) async throws -> Value {
    do {
        return try await operation()
    } catch {
        throw ContextError(message(), cause: error)
    }
}

/// The text of an error for logs and stored messages. It prefers an error's debug description, because some errors,
/// such as PostgresNIO's, keep the details out of their plain description.
public func errorDescription(_ error: any Error) -> String {
    String(reflecting: error)
}
