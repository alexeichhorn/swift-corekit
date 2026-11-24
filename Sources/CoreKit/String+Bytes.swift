extension String {
    /// The string cut to at most `count` bytes of UTF-8, like Rust's `&text[..count]`. A code point that would be cut in
    /// half is left out, so the result can be shorter than `count` bytes. A character made of several code points, such
    /// as a flag, can lose its later ones.
    public func prefix(bytes count: Int) -> String {
        guard utf8.count > count else { return self }
        var end = utf8.index(utf8.startIndex, offsetBy: max(count, 0))
        while end.samePosition(in: unicodeScalars) == nil {
            end = utf8.index(before: end)
        }
        return String(self[..<end])
    }
}
