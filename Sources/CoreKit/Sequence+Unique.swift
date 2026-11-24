extension Sequence {
    /// The first element of each key, in the order of the elements: `visits.uniqued(on: \.userID)`.
    public func uniqued<Key: Hashable>(on key: (Element) throws -> Key) rethrows -> [Element] {
        var seen: Set<Key> = []
        return try filter { seen.insert(try key($0)).inserted }
    }
}
