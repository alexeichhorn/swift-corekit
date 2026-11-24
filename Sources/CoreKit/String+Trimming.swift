extension StringProtocol {
    /// The string without the whitespace at both ends, like Rust's `trim()`: whitespace is every code point with
    /// Unicode's `White_Space` property, which includes the no-break space and excludes the zero-width space.
    public func trimmingWhitespace() -> String {
        var scalars = Substring(self).unicodeScalars
        while scalars.first?.properties.isWhitespace == true { scalars.removeFirst() }
        while scalars.last?.properties.isWhitespace == true { scalars.removeLast() }
        return String(Substring(scalars))
    }
}
