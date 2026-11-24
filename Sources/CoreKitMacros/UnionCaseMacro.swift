import SwiftSyntax
import SwiftSyntaxMacros

/// `@Tag` and `@UnknownTag`: markers that expand to nothing. `@Schema(tag:)` reads them from the enum's cases, and each
/// marker reports its own malformed argument or unsupported case.
public struct UnionCaseMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let elements = declaration.as(EnumCaseDeclSyntax.self)?.elements, let element = elements.first, elements.count == 1 else {
            throw MacroError("@\(node.name) needs an enum case that is declared on its own")
        }
        switch node.name {
        case "Tag":
            _ = try tagValue(of: node)
        case "UnknownTag" where element.parameterClause != nil:
            throw MacroError("The @UnknownTag case can't have an associated value, since an unknown tag has no known payload")
        default:
            break
        }
        return []
    }

    /// The tag value that a `@Tag` attribute gives its case.
    static func tagValue(of attribute: AttributeSyntax) throws -> String {
        let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) ?? []
        guard arguments.count == 1, let value = arguments.first.flatMap({ literalValue(of: $0.expression) }), !value.isEmpty else {
            throw MacroError("@Tag takes one string literal: @Tag(\"order.created\")")
        }
        return value
    }
}
