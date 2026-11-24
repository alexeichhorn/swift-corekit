/// A size in bytes, written as `"512kb"`, `"10mb"` or a plain byte count.
public struct ByteCount: Sendable, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    public let bytes: Int

    public init(integerLiteral bytes: Int) {
        self.bytes = bytes
    }

    /// Accepts `b`, `kb`, `mb` and `gb` (powers of 1024), case-insensitively. Anything else is a programming error, which
    /// the route macros report at compile time.
    public init(stringLiteral value: String) {
        let units: [(suffix: String, factor: Int)] = [("gb", 1 << 30), ("mb", 1 << 20), ("kb", 1 << 10), ("b", 1)]
        let lowercased = value.lowercased()
        let (number, factor) =
            units.first { lowercased.hasSuffix($0.suffix) }.map { (lowercased.dropLast($0.suffix.count), $0.factor) }
            ?? (Substring(lowercased), 1)
        guard let count = Int(number) else { preconditionFailure("Invalid byte count '\(value)'") }
        self.bytes = count * factor
    }
}
