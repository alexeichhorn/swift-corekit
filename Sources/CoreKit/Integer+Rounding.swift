extension BinaryInteger {
    /// This value divided by a positive `divisor`, rounded up: `7.dividedRoundingUp(by: 2)` is `4`.
    public func dividedRoundingUp(by divisor: Self) -> Self {
        let (quotient, remainder) = quotientAndRemainder(dividingBy: divisor)
        return remainder > 0 ? quotient + 1 : quotient
    }

    /// The smallest multiple of a positive `step` that is at least this value: `18.roundedUp(toMultipleOf: 16)` is `32`.
    public func roundedUp(toMultipleOf step: Self) -> Self {
        dividedRoundingUp(by: step) * step
    }
}
