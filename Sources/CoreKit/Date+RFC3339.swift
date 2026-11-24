import Foundation

extension Date {
    /// The date in UTC as RFC 3339 text with a numeric zone: `2026-11-14T12:34:56+00:00`. A fraction is written only
    /// when the date has one, with three digits for milliseconds and six for microseconds.
    public var rfc3339: String {
        let microseconds = Int64((timeIntervalSince1970 * 1_000_000).rounded())
        var (seconds, fraction) = microseconds.quotientAndRemainder(dividingBy: 1_000_000)
        if fraction < 0 {
            seconds -= 1
            fraction += 1_000_000
        }

        let dateTime = Date(timeIntervalSince1970: TimeInterval(seconds))
            .formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon))
        let digits = String(fraction + 1_000_000).dropFirst()
        let fractionText =
            switch fraction {
            case 0: ""
            case _ where fraction % 1000 == 0: ".\(digits.prefix(3))"
            default: ".\(digits)"
            }
        return "\(dateTime)\(fractionText)+00:00"
    }
}
