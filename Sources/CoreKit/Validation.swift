/// A constraint on a value, named after its JSON Schema keyword. `@Length`, `@Range` and `@Pattern` attach them.
public indirect enum ValidationRule: Sendable, Hashable, CustomStringConvertible {
    /// Counted in Unicode scalars.
    case minLength(Int)
    case maxLength(Int)
    case minItems(Int)
    case maxItems(Int)
    case minimum(Double)
    case maximum(Double)
    /// A regular expression that has to match somewhere in the string.
    case pattern(String)
    /// Rules for every item of an array. A violation is reported for the item, with the rule it broke.
    case items([ValidationRule])

    /// The rule as a requirement: `must have at least 3 characters`.
    public var description: String {
        switch self {
        case .minLength(let count): "must have at least \(count) character\(count == 1 ? "" : "s")"
        case .maxLength(let count): "must have at most \(count) character\(count == 1 ? "" : "s")"
        case .minItems(let count): "must have at least \(count) item\(count == 1 ? "" : "s")"
        case .maxItems(let count): "must have at most \(count) item\(count == 1 ? "" : "s")"
        case .minimum(let bound): "must be at least \(Self.number(bound).serialized())"
        case .maximum(let bound): "must be at most \(Self.number(bound).serialized())"
        case .pattern(let pattern): "must match the pattern \(pattern)"
        case .items(let rules): "every item \(rules.map(\.description).joined(separator: " and "))"
        }
    }

    /// The rule as a keyword of its schema. Item rules have none: they belong to the schema of the items.
    var keyword: (key: String, value: JSONValue) {
        switch self {
        case .minLength(let count): ("minLength", .int(count))
        case .maxLength(let count): ("maxLength", .int(count))
        case .minItems(let count): ("minItems", .int(count))
        case .maxItems(let count): ("maxItems", .int(count))
        case .minimum(let bound): ("minimum", Self.number(bound))
        case .maximum(let bound): ("maximum", Self.number(bound))
        case .pattern(let pattern): ("pattern", .string(pattern))
        case .items: preconditionFailure("item rules are part of the items' schema")
        }
    }

    /// A whole bound as an integer, so `@Range(1...20)` reads `1` and `20`.
    private static func number(_ bound: Double) -> JSONValue {
        Int(exactly: bound).map(JSONValue.int) ?? .double(bound)
    }
}

/// One violated rule and the value that violates it.
public struct ValidationIssue: Sendable, Hashable, CustomStringConvertible {
    /// The way from the validated value to the offending one, in JSON keys and array indices.
    public let path: [PathElement]
    public let rule: ValidationRule

    public init(path: [PathElement], rule: ValidationRule) {
        self.path = path
        self.rule = rule
    }

    /// The path joined by dots, then the rule: `filters.0.query: must have at least 3 characters`.
    public var description: String {
        let path = path.map { element in
            switch element {
            case .key(let key): key
            case .index(let index): String(index)
            }
        }
        return "\(path.joined(separator: ".")): \(rule)"
    }

    public enum PathElement: Sendable, Hashable {
        /// An object key as on the wire, so snake_case for `@Schema` structs.
        case key(String)
        case index(Int)
    }
}

/// Thrown by `validate()`; lists every violated rule.
public struct ValidationError: Error, CustomStringConvertible {
    public let issues: [ValidationIssue]

    public var description: String { issues.map(\.description).joined(separator: "; ") }
}

extension SchemaRepresentable {
    public func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {}

    /// Checks the constraints of this value and of every value nested in it.
    public func validate() throws(ValidationError) {
        var issues: [ValidationIssue] = []
        validate([], at: [], into: &issues)
        if !issues.isEmpty { throw ValidationError(issues: issues) }
    }
}

extension String {
    public func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {
        rules.check(at: path, into: &issues) { rule in
            switch rule {
            case .minLength(let count): unicodeScalars.count >= count
            case .maxLength(let count): unicodeScalars.count <= count
            case .pattern(let pattern): contains(Self.regex(pattern))
            default: true
            }
        }
    }

    /// The pattern as OpenAI reads a schema's: matched by code point, so `.` is one code point and not a letter with
    /// its accents, with `\d` and `\w` covering ASCII only and `\s` any Unicode whitespace.
    private static func regex(_ pattern: String) -> Regex<AnyRegexOutput> {
        do {
            return try Regex(pattern).matchingSemantics(.unicodeScalar).asciiOnlyDigits().asciiOnlyWordCharacters()
        } catch {
            fatalError("Invalid regular expression '\(pattern)': \(error)")
        }
    }
}

extension SchemaRepresentable where Self: BinaryInteger {
    public func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {
        rules.check(Double(self), at: path, into: &issues)
    }
}

extension SchemaRepresentable where Self: BinaryFloatingPoint {
    public func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {
        // Compared in the value's own type: `0.1` as a `Float` is a little more than `0.1` as a `Double`.
        rules.check(at: path, into: &issues) { rule in
            switch rule {
            case .minimum(let bound): self >= Self(bound)
            case .maximum(let bound): self <= Self(bound)
            default: true
            }
        }
    }
}

extension Optional where Wrapped: SchemaRepresentable {
    public func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {
        self?.validate(rules, at: path, into: &issues)
    }
}

extension Array where Element: SchemaRepresentable {
    public func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {
        rules.check(at: path, into: &issues) { rule in
            switch rule {
            case .minItems(let count): self.count >= count
            case .maxItems(let count): self.count <= count
            default: true
            }
        }
        for (index, element) in enumerated() {
            element.validate(rules.forItems, at: path + [.index(index)], into: &issues)
        }
    }
}

extension Dictionary where Key == String, Value: SchemaRepresentable {
    public func validate(_ rules: [ValidationRule], at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {
        // Sorted, so the issues come in the same order every time.
        for (key, value) in sorted(by: { $0.key < $1.key }) {
            value.validate([], at: path + [.key(key)], into: &issues)
        }
    }
}

extension [ValidationRule] {
    /// The rules given for an array's items.
    var forItems: [ValidationRule] {
        flatMap { rule -> [ValidationRule] in
            if case .items(let rules) = rule { rules } else { [] }
        }
    }

    /// Appends an issue at `path` for every rule `isSatisfied` returns false for.
    fileprivate func check(
        at path: [ValidationIssue.PathElement],
        into issues: inout [ValidationIssue],
        isSatisfied: (ValidationRule) -> Bool
    ) {
        issues += filter { !isSatisfied($0) }.map { ValidationIssue(path: path, rule: $0) }
    }

    fileprivate func check(_ number: Double, at path: [ValidationIssue.PathElement], into issues: inout [ValidationIssue]) {
        check(at: path, into: &issues) { rule in
            switch rule {
            case .minimum(let bound): number >= bound
            case .maximum(let bound): number <= bound
            default: true
            }
        }
    }
}
