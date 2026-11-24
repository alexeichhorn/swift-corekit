import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@PublicInit`: a public initializer with one parameter per stored property.
public struct PublicInitMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            throw MacroError("@PublicInit can only be applied to a struct")
        }
        // A `let` with an initializer already has its value.
        let properties = declaration.storedProperties.filter { !($0.isLet && $0.initializer != nil) }
        let parameters = try properties.map { property in
            guard let type = property.type else {
                throw MacroError("@PublicInit needs a type annotation on `\(property.name)`")
            }
            let escaping = type.isFunction ? "@escaping " : ""
            let defaultValue = property.initializer.map { " = \($0)" } ?? ""
            return "\(property.identifier): \(escaping)\(type)\(defaultValue)"
        }
        guard !parameters.isEmpty else { return ["public init() {}"] }
        let assignments = properties.map { "self.\($0.identifier) = \($0.identifier)" }
        return [
            """
            public init(
                \(raw: indented(parameters.joined(separator: ",\n"), by: 4))
            ) {
                \(raw: indented(assignments.joined(separator: "\n"), by: 4))
            }
            """
        ]
    }
}

extension TypeSyntax {
    /// A closure type, with or without parentheses and attributes such as `@Sendable`. An Optional closure isn't one,
    /// and a type alias of a closure can't be recognized.
    fileprivate var isFunction: Bool {
        if self.is(FunctionTypeSyntax.self) { return true }
        if let attributed = self.as(AttributedTypeSyntax.self) { return attributed.baseType.isFunction }
        if let tuple = self.as(TupleTypeSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first {
            return only.firstName == nil && only.type.isFunction
        }
        return false
    }
}
