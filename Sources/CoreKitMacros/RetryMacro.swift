import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Retry`: runs the function's body through `CoreKit.retry`, which receives the attribute's arguments as written.
public struct RetryMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        try wrappedBody(of: declaration, attribute: node, calling: "CoreKit.retry")
    }
}

/// `@Timeout`: runs the function's body through `CoreKit.withTimeout`.
public struct TimeoutMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        try wrappedBody(of: declaration, attribute: node, calling: "CoreKit.withTimeout")
    }
}

/// The body as a closure passed to `wrapper` after the attribute's arguments.
private func wrappedBody(
    of declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    attribute: AttributeSyntax,
    calling wrapper: String
) throws -> [CodeBlockItemSyntax] {
    guard let function = declaration.as(FunctionDeclSyntax.self), let body = function.body,
        let effects = function.signature.effectSpecifiers, effects.asyncSpecifier != nil,
        let throwsClause = effects.throwsClause, throwsClause.type == nil
    else {
        throw MacroError("@\(attribute.name) requires an 'async throws' function")
    }
    // Swift expands only one body macro per function and drops the other without a word.
    let other = attribute.name == "Retry" ? "Timeout" : "Retry"
    if function.attributes.contains(where: { $0.as(AttributeSyntax.self)?.name == other }) {
        throw MacroError("@Retry and @Timeout can't be combined on one function; write @Retry(..., timeout: ...) instead")
    }
    let arguments = attribute.arguments?.trimmedDescription ?? ""
    return ["return try await \(raw: wrapper)(\(raw: arguments)) {\(body.statements)}"]
}
