import SwiftSyntax
import SwiftSyntaxMacros

/// `@Length`, `@Range`, `@Pattern`: markers that expand to nothing. `@Schema` and `@EnvConfig` read them from the
/// property, and each marker reports its own malformed arguments or unsupported property type.
public struct ConstraintMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let type = declaration.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type else {
            throw MacroError("@\(node.name) needs a property with an explicit type")
        }
        _ = try rules(of: node, on: type)
        return []
    }

    /// The `ValidationRule` expressions `attribute` stands for on a property of `type`; none for other attributes.
    static func rules(of attribute: AttributeSyntax, on type: TypeSyntax) throws -> [String] {
        let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) ?? []
        let kind = ValueKind(type)
        switch attribute.name {
        case "Length":
            guard let kind, !kind.isNumber, kind != .other else {
                throw MacroError("@Length applies to String and array properties, not '\(type.trimmed)'")
            }
            return try lengthBounds(arguments).map { ".\($0.label)\(kind == .string ? "Length" : "Items")(\($0.count))" }
        case "Range":
            let number = if case .array(let element) = kind { element } else { kind }
            guard let number, number.isNumber else {
                throw MacroError("@Range applies to integer and floating-point properties and arrays of them, not '\(type.trimmed)'")
            }
            let (lower, upper) = try rangeBounds(arguments, ofIntegers: number == .integer)
            let rules = [lower.map { ".minimum(\($0))" }, upper.map { ".maximum(\($0))" }].compactMap(\.self)
            return kind == number ? rules : [".items([\(rules.joined(separator: ", "))])"]
        case "Pattern":
            guard kind == .string || kind == .array(of: .string) else {
                throw MacroError("@Pattern applies to String properties and arrays of them, not '\(type.trimmed)'")
            }
            guard arguments.count == 1, let literal = arguments.first?.expression.as(StringLiteralExprSyntax.self),
                let pattern = literal.representedLiteralValue
            else {
                throw MacroError("@Pattern takes one string literal: @Pattern(\"^[a-z]{2}$\")")
            }
            do {
                _ = try Regex(pattern)
            } catch {
                throw MacroError("@Pattern needs a valid regular expression: \(error)")
            }
            return kind == .string ? [".pattern(\(literal.trimmed))"] : [".items([.pattern(\(literal.trimmed))])"]
        default:
            return []
        }
    }

    /// `min` and `max` in that order, as the macro declares them.
    private static func lengthBounds(_ arguments: LabeledExprListSyntax) throws -> [(label: String, count: Int)] {
        let bounds = arguments.compactMap { argument -> (label: String, count: Int)? in
            guard let label = argument.label?.text, let count = argument.expression.as(IntegerLiteralExprSyntax.self).flatMap(number)
            else { return nil }
            return (label, Int(count))
        }
        let counts = bounds.map(\.count)
        guard !bounds.isEmpty, bounds.count == arguments.count, counts == counts.sorted() else {
            throw MacroError("@Length takes integer literals with min at most max: @Length(min: 3, max: 200)")
        }
        return bounds
    }

    /// - Parameter ofIntegers: Whether the bounds limit an integer. Values are compared as `Double`s, which is exact
    ///   for every integer only while the bound is at most 2^53 - 1 in size, so a larger one is refused.
    private static func rangeBounds(_ arguments: LabeledExprListSyntax, ofIntegers: Bool) throws -> (
        lower: ExprSyntax?, upper: ExprSyntax?
    ) {
        let error = MacroError("@Range takes inclusive bounds of number literals: @Range(1...20), @Range(1...) or @Range(...20)")
        guard arguments.count == 1, let expression = arguments.first?.expression else { throw error }
        let bounds: (lower: ExprSyntax?, upper: ExprSyntax?)
        // The compiler hands over `1...20` folded into an infix expression; unfolded source has a sequence.
        if let closed = expression.as(InfixOperatorExprSyntax.self), closed.operator.trimmedDescription == "..." {
            bounds = (closed.leftOperand.trimmed, closed.rightOperand.trimmed)
        } else if let elements = expression.as(SequenceExprSyntax.self)?.elements.map(\.trimmed), elements.count == 3,
            elements[1].trimmedDescription == "..."
        {
            bounds = (elements[0], elements[2])
        } else if let from = expression.as(PostfixOperatorExprSyntax.self), from.operator.text == "..." {
            bounds = (from.expression.trimmed, nil)
        } else if let through = expression.as(PrefixOperatorExprSyntax.self), through.operator.text == "..." {
            bounds = (nil, through.expression.trimmed)
        } else {
            throw error
        }
        let given = [bounds.lower, bounds.upper].compactMap(\.self)
        let numbers = given.compactMap(number)
        guard numbers.count == given.count, numbers == numbers.sorted() else { throw error }
        if ofIntegers, numbers.contains(where: { abs($0) > 9_007_199_254_740_991 }) {
            throw MacroError("@Range bounds of an integer property must lie between -9007199254740991 and 9007199254740991")
        }
        return bounds
    }

    /// The value of a number literal, which may be negative.
    private static func number(_ expression: some ExprSyntaxProtocol) -> Double? {
        if let negated = expression.as(PrefixOperatorExprSyntax.self), negated.operator.text == "-" {
            return number(negated.expression).map { -$0 }
        }
        let literal = expression.as(IntegerLiteralExprSyntax.self)?.literal ?? expression.as(FloatLiteralExprSyntax.self)?.literal
        return literal.flatMap { Double($0.text.filter { $0 != "_" }) }
    }
}

/// What a constraint can measure, judged by the type as written.
private indirect enum ValueKind: Equatable {
    case string
    case array(of: ValueKind)
    case integer
    case floatingPoint
    /// A type no constraint applies to; only met as the element of an array.
    case other

    var isNumber: Bool { self == .integer || self == .floatingPoint }

    init?(_ type: TypeSyntax) {
        if let optional = type.as(OptionalTypeSyntax.self) {
            self.init(optional.wrappedType)
        } else if let array = type.as(ArrayTypeSyntax.self) {
            self = .array(of: ValueKind(array.element) ?? .other)
        } else {
            let identifier = type.as(IdentifierTypeSyntax.self)
            switch identifier?.name.text {
            case "Optional":
                guard let wrapped = identifier?.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) else { return nil }
                self.init(wrapped)
            case "String": self = .string
            case "Array":
                let element = identifier?.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self)
                self = .array(of: element.flatMap(ValueKind.init) ?? .other)
            case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64": self = .integer
            case "Double", "Float": self = .floatingPoint
            default: return nil
            }
        }
    }
}
