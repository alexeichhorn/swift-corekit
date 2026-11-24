extension Sequence {
    /// The elements in order of a property, ascending unless `descending` is set: `products.sorted(by: \.name)`.
    public func sorted<Value: Comparable>(by keyPath: KeyPath<Element, Value>, descending: Bool = false) -> [Element] {
        sorted { descending ? $0[keyPath: keyPath] > $1[keyPath: keyPath] : $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }
}
