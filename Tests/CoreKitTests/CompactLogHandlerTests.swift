import Foundation
import Logging
import Testing

@testable import CoreKit

/// The line as `tracing`'s compact format writes it, colour codes included, with the fields sorted by key.
@Test func compactLogLinesLookLikeTracingsCompactFormat() {
    let line = CompactLogHandler.line(
        at: Date(timeIntervalSince1970: 1_767_323_045.678901),
        level: .warning,
        label: "order-api",
        message: "Created order",
        fields: ["owner": "alice", "id": "42"]
    )
    let escape = "\u{1B}"
    #expect(
        line == "\(escape)[2m2026-01-02T03:04:05.678901Z\(escape)[0m \(escape)[33m WARN\(escape)[0m "
            + "\(escape)[2morder-api\(escape)[0m\(escape)[2m:\(escape)[0m Created order"
            + " \(escape)[3mid\(escape)[0m\(escape)[2m=\(escape)[0m42"
            + " \(escape)[3mowner\(escape)[0m\(escape)[2m=\(escape)[0malice")
}

/// What the handler adds to a line: the metadata of every `withLogMetadata` around the task, also in a task started inside.
@Test func logMetadataReachesNestedCallsAndChildTasks() async {
    #expect(LogContext.metadata.isEmpty)
    await withLogMetadata(["order_id": "42", "step": "pack"]) {
        await withLogMetadata(["step": "ship"]) {
            let inChildTask = await Task { LogContext.metadata }.value
            #expect(inChildTask == ["order_id": "42", "step": "ship"])
        }
        #expect(LogContext.metadata == ["order_id": "42", "step": "pack"])
    }
    #expect(LogContext.metadata.isEmpty)
}

/// The handler writes to standard output, so the test logs in a child process: a line carries the metadata of the
/// `withLogMetadata` around it, and a message below the level is left out.
@Test func handlerWritesTheMetadataOfTheSurroundingTask() async {
    let result = await #expect(processExitsWith: .success, observing: [\.standardOutputContent]) {
        let logger = Logger(label: "order-api") { CompactLogHandler(label: $0, logLevel: .info) }
        await withLogMetadata(["order_id": "42"]) {
            logger.debug("Packing order")
            logger.info("Shipped order", metadata: ["carrier": "post"])
        }
    }
    let output = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self).replacing(/\u{1B}\[[0-9;]*m/, with: "")

    #expect(output.hasSuffix(" INFO order-api: Shipped order carrier=post order_id=42\n"))
    #expect(!output.contains("Packing order"))
}
