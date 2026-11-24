import SwiftSyntax
import SwiftSyntaxBuilder

struct StoredProperty {
    /// The identifier as written, including backticks.
    let identifier: String
    /// The identifier without backticks.
    let name: String
    let type: TypeSyntax?
    let initializer: ExprSyntax?
    let isLet: Bool
    let documentation: String?
    let attributes: AttributeListSyntax

    /// The `ValidationRule` expressions of the property's constraint attributes. A malformed attribute contributes
    /// none; it reports the error itself.
    var rules: [String] {
        guard let type else { return [] }
        return attributes.compactMap { $0.as(AttributeSyntax.self) }.flatMap { (try? ConstraintMacro.rules(of: $0, on: type)) ?? [] }
    }
}

extension DeclGroupSyntax {
    var storedProperties: [StoredProperty] {
        memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { variable in !variable.modifiers.contains { ["static", "class"].contains($0.name.text) } }
            .flatMap { variable in
                variable.bindings.compactMap { binding -> StoredProperty? in
                    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self), binding.isStored else { return nil }
                    let identifier = pattern.identifier.text
                    return StoredProperty(
                        identifier: identifier,
                        name: identifier.filter { $0 != "`" },
                        type: binding.typeAnnotation?.type.trimmed,
                        initializer: binding.initializer?.value.trimmed,
                        isLet: variable.bindingSpecifier.tokenKind == .keyword(.let),
                        documentation: variable.leadingTrivia.documentation,
                        attributes: variable.attributes
                    )
                }
            }
    }

    /// `public ` or `package ` when the type declares it, so generated members match the type's visibility.
    var accessPrefix: String {
        modifiers.first { ["public", "package"].contains($0.name.text) }.map { "\($0.name.text) " } ?? ""
    }
}

extension PatternBindingSyntax {
    /// False for computed properties; observed properties (`willSet`/`didSet`) are stored.
    var isStored: Bool {
        switch accessorBlock?.accessors {
        case nil: true
        case .getter?: false
        case .accessors(let accessors)?:
            accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        }
    }
}

extension AttributeSyntax {
    /// The attribute's name without a module qualifier: `Range` for `@CoreKit.Range(1...)`.
    var name: String {
        attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
    }
}

extension Trivia {
    /// The `///` doc comment, with one line per comment line.
    var documentation: String? {
        let lines = compactMap { piece -> String? in
            guard case .docLineComment(let text) = piece else { return nil }
            let line = text.dropFirst(3)
            return String(line.first == " " ? line.dropFirst() : line)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

extension TypeSyntax {
    var isOptional: Bool {
        optionalWrapped != nil
    }

    /// `T` of `T?`, `Optional<T>` and `Swift.Optional<T>`; `nil` for any other type, also for an alias of an optional.
    var optionalWrapped: TypeSyntax? {
        if let optional = self.as(OptionalTypeSyntax.self) { return optional.wrappedType.trimmed }
        let arguments: GenericArgumentClauseSyntax?
        if let identifier = self.as(IdentifierTypeSyntax.self), identifier.name.text == "Optional" {
            arguments = identifier.genericArgumentClause
        } else if let member = self.as(MemberTypeSyntax.self), member.trimmedDescription.hasPrefix("Swift.Optional<") {
            arguments = member.genericArgumentClause
        } else {
            return nil
        }
        return arguments?.arguments.first?.argument.as(TypeSyntax.self)?.trimmed
    }
}

/// Swift source for a string literal, escaped as needed.
func stringLiteral(_ content: String) -> String {
    StringLiteralExprSyntax(content: content).trimmedDescription
}

func optionalStringLiteral(_ content: String?) -> String {
    content.map(stringLiteral) ?? "nil"
}

/// The value of a string literal without interpolations, with its escapes interpreted, e.g. a route path.
func literalValue(of expression: ExprSyntax) -> String? {
    expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
}

/// Indents every line after the first, for multi-line code interpolated at an indented position.
func indented(_ code: String, by spaces: Int) -> String {
    code.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n" + String(repeating: " ", count: spaces))
}
