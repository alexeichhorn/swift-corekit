import CoreKit

final class Report {
    var title = ""
}

// With a timeout the body runs in a child task, so what it captures must be Sendable.
@Timeout(.seconds(1))
func render(_ report: Report) async throws -> String { report.title }  // error: non-Sendable type 'Report'

@Retry(maxRetries: 1, timeout: .seconds(1))
func renderAttempts(_ report: Report) async throws -> String { report.title }  // error: non-Sendable type 'Report'

// Swift expands only one body macro per function, so each reports the other.
@Retry(maxRetries: 4)  // error: @Retry and @Timeout can't be combined
@Timeout(.seconds(30))  // error: @Retry and @Timeout can't be combined
func renderBoth() async throws {}

@Retry  // error: @Retry requires an 'async throws' function
func renderWithoutThrowing() async {}
