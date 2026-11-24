extension Sequence where Element: Sendable {
    /// Transforms every element at the same time, or at most `maxConcurrency` at a time, and returns the results in the
    /// order of the elements. The first error ends the call and cancels the transformations still running; a
    /// transformation that cannot throw needs no `try`.
    ///
    /// ```swift
    /// let pages = try await urls.concurrentMap(maxConcurrency: 4) { try await fetch($0) }
    /// ```
    public func concurrentMap<Value: Sendable, Failure: Error>(
        maxConcurrency: Int? = nil,
        _ transform: @escaping @Sendable (Element) async throws(Failure) -> Value
    ) async throws(Failure) -> [Value] {
        let finished = await withTaskGroup(of: (offset: Int, result: Result<Value, Failure>).self) { group in
            var waiting = enumerated().makeIterator()
            var finished: [(offset: Int, result: Result<Value, Failure>)] = []

            @discardableResult
            func startNext() -> Bool {
                guard let (offset, element) = waiting.next() else { return false }
                group.addTask { (offset, await outcome(of: transform, for: element)) }
                return true
            }

            let limit = maxConcurrency.map { Swift.max($0, 1) } ?? .max
            var started = 0
            while started < limit, startNext() { started += 1 }
            while let next = await group.next() {
                finished.append(next)
                if case .failure = next.result {
                    group.cancelAll()
                    break
                }
                startNext()
            }
            return finished
        }
        return try finished.sorted { $0.offset < $1.offset }.map { result throws(Failure) in try result.result.get() }
    }
}

/// What `transform` returns for `element`, or the error it throws.
private func outcome<Element, Value, Failure: Error>(
    of transform: (Element) async throws(Failure) -> Value, for element: Element
) async -> Result<Value, Failure> {
    do {
        return .success(try await transform(element))
    } catch {
        return .failure(error)
    }
}
