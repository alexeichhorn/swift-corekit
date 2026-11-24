import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@EnvConfig`: a `load()` that builds the struct through its memberwise initializer from environment variables.
public struct EnvConfigMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            throw MacroError("@EnvConfig can only be applied to a struct")
        }
        // A `let` with an initializer isn't part of the memberwise initializer.
        let properties = declaration.storedProperties.filter { !($0.isLet && $0.initializer != nil) }
        var requiredKeys: [String] = []
        let arguments = properties.map { property in
            let key = stringLiteral(Naming.screamingSnakeCase(property.name))
            let defaultValue = property.initializer.flatMap { $0.is(NilLiteralExprSyntax.self) ? nil : $0 }
            var value: String
            if property.type?.isOptional ?? false {
                value = "reader.optional(\(key))" + (defaultValue.map { " ?? \($0)" } ?? "")
            } else if let defaultValue {
                value = "reader.value(\(key), default: \(defaultValue))"
            } else {
                requiredKeys.append(key)
                value = "reader.required(\(key))"
            }
            let rules = property.rules
            if !rules.isEmpty { value = "reader.checked(\(value), [\(rules.joined(separator: ", "))], for: \(key))" }
            return "\(property.identifier): \(value)"
        }
        var body = ["let reader = CoreKit.EnvReader()"]
        if !requiredKeys.isEmpty {
            body.append("reader.checkRequired([\(requiredKeys.joined(separator: ", "))])")
        }
        body.append("return Self(\n    \(indented(arguments.joined(separator: ",\n"), by: 4))\n)")
        let conformance = protocols.isEmpty ? "" : ": Sendable"
        let extensionDecl: DeclSyntax = """
            extension \(type.trimmed)\(raw: conformance) {
                /// Reads the configuration from the process environment and the working directory's `.env`.
                \(raw: declaration.accessPrefix)static func load() -> Self {
                    \(raw: indented(body.joined(separator: "\n"), by: 8))
                }
            }
            """
        return [extensionDecl.cast(ExtensionDeclSyntax.self)]
    }
}
