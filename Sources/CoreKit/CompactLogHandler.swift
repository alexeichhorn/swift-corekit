import Foundation
import Logging

/// Writes each message as one coloured line to standard output, in the compact form of Rust's `tracing`:
/// `2026-01-02T03:04:05.678901Z  INFO order-api: Created order id=42 owner=alice`.
///
/// The colours are ANSI codes and are always written, so a log viewer that renders them shows the level in colour:
/// `LoggingSystem.bootstrap { CompactLogHandler(label: $0, logLevel: .info) }`.
public struct CompactLogHandler: LogHandler {
    public var logLevel: Logger.Level
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?
    private let label: String

    public init(label: String, logLevel: Logger.Level = .info, metadataProvider: Logger.MetadataProvider? = nil) {
        self.label = label
        self.logLevel = logLevel
        self.metadataProvider = metadataProvider
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        var fields = metadata
        fields.merge(LogContext.metadata) { $1 }
        fields.merge(metadataProvider?.get() ?? [:]) { $1 }
        fields.merge(event.metadata ?? [:]) { $1 }
        if let error = event.error, fields["error"] == nil { fields["error"] = "\(error)" }

        let line = Self.line(at: Date(), level: event.level, label: label, message: event.message.description, fields: fields)
        // One write per line, so lines of concurrent tasks don't mix and nothing waits in a buffer.
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// The line without its newline. Fields come sorted by key, since metadata has no order of its own.
    static func line(at date: Date, level: Logger.Level, label: String, message: String, fields: Logger.Metadata) -> String {
        let (name, color) =
            switch level {
            case .trace: ("TRACE", "35")
            case .debug: ("DEBUG", "34")
            case .info: (" INFO", "32")
            case .notice: (" NOTE", "32")
            case .warning: (" WARN", "33")
            case .error: ("ERROR", "31")
            case .critical: (" CRIT", "31")
            }
        let renderedFields = fields.sorted { $0.key < $1.key }.map { " \(italic)\($0.key)\(reset)\(dim)=\(reset)\($0.value)" }.joined()
        return
            "\(dim)\(timestamp(date))\(reset) \u{1B}[\(color)m\(name)\(reset) \(dim)\(label)\(reset)\(dim):\(reset) \(message)\(renderedFields)"
    }

    /// UTC with microseconds: `2026-11-18T14:01:44.377605Z`.
    private static func timestamp(_ date: Date) -> String {
        let microseconds = Int64((date.timeIntervalSince1970 * 1_000_000).rounded(.down))
        let seconds = Date(timeIntervalSince1970: TimeInterval(microseconds.quotientAndRemainder(dividingBy: 1_000_000).quotient))
        let fraction = String(1_000_000 + microseconds % 1_000_000).dropFirst()
        let dateTime = seconds.formatted(
            .iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon))
        return "\(dateTime).\(fraction)Z"
    }

    private static let dim = "\u{1B}[2m"
    private static let italic = "\u{1B}[3m"
    private static let reset = "\u{1B}[0m"
}
