extension Duration {
    /// The whole milliseconds, e.g. for a `duration_ms` log field: `(ContinuousClock.now - start).milliseconds`.
    public var milliseconds: Int64 {
        components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}
