public import Logging

/// The metadata `withLogMetadata` set for the current task.
enum LogContext {
    @TaskLocal static var metadata: Logger.Metadata = [:]
}

/// Runs `operation` with `metadata` on every log line written inside it, by any logger and by the tasks it starts. A call
/// inside another adds to the outer metadata.
///
/// ```swift
/// try await withLogMetadata(["order_id": "\(order.id)"]) {
///     try await ship(order)  // every line logged in here carries order_id
/// }
/// ```
///
/// ``CompactLogHandler`` is the handler that writes it.
public func withLogMetadata<Value>(_ metadata: Logger.Metadata, _ operation: () async throws -> Value) async rethrows -> Value {
    try await LogContext.$metadata.withValue(LogContext.metadata.merging(metadata) { _, new in new }, operation: operation)
}
