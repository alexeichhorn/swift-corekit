/// A string that never shows up in logs, `print`, string interpolation, or `dump`.
public struct Secret: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The real value. Read it only where it's handed to its consumer, e.g. an API client.
    public let exposedValue: String

    public init(_ value: String) {
        self.exposedValue = value
    }

    public var description: String { "<redacted>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: []) }
}
