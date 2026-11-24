extension Collection {
    /// The element at an index, or `nil` when the collection has none there: `names[safe: 3]`.
    public subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
