import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Schema`: snake_case `CodingKeys` (structs) or `Codable` (union enums) plus a `SchemaRepresentable` conformance.
///
/// A `Decodable` struct with a `var` that has an initial value also gets its `init(from:)`, in which a missing key
/// leaves that value.
///
/// The conformance's `validate` checks each property against its constraint attributes and passes on to the property,
/// or to a union's wrapped value, so nested values are validated by their own types.
///
/// Schemas are named after the type's full nesting path (`Page.Section.Item`), so nested types don't collide, unless
/// the attribute gives a `name:`.
public struct SchemaMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            // Invalid enums are diagnosed once, by the extension expansion.
            return (try? SchemaEnum(enumDecl, tag: tag(of: node)))?.members(access: declaration.accessPrefix) ?? []
        }
        guard declaration.is(StructDeclSyntax.self) else { return [] }
        if try tag(of: node) != nil { throw MacroError("@Schema(tag:) can only be applied to an enum") }
        let declaresCodingKeys = declaration.memberBlock.members.contains {
            $0.decl.as(EnumDeclSyntax.self)?.name.text == "CodingKeys"
        }
        if declaresCodingKeys {
            throw MacroError("@Schema generates CodingKeys from the property names; remove the custom CodingKeys")
        }
        let properties = declaration.storedProperties
        guard !properties.isEmpty else { return [] }
        let cases = properties.map { property in
            let key = Naming.snakeCase(property.name)
            return key == property.name ? "case \(property.identifier)" : "case \(property.identifier) = \(stringLiteral(key))"
        }
        return ["enum CodingKeys: String, CodingKey {\n\(raw: cases.joined(separator: "\n"))\n}"]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Nested types arrive qualified by their enclosing types.
        let name = try name(of: node) ?? type.trimmedDescription
        let schema: String
        let validation: String?
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            schema = try objectSchema(structDecl, name: name)
            validation = objectValidation(structDecl)
        } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            let schemaEnum = try SchemaEnum(enumDecl, tag: tag(of: node))
            schema = schemaEnum.schema(name: name, description: enumDecl.leadingTrivia.documentation)
            validation = schemaEnum.validation
        } else {
            throw MacroError("@Schema can only be applied to a struct or an enum")
        }
        var members = ["public static var jsonSchema: CoreKit.JSONSchema {\n    \(indented(schema, by: 4))\n}"]
        if let decoding = declaration.as(StructDeclSyntax.self).flatMap(decodingInitializer) {
            members.insert(decoding, at: 0)
        }
        if let validation {
            members.append(
                """
                public func validate(
                    _ rules: [CoreKit.ValidationRule],
                    at path: [CoreKit.ValidationIssue.PathElement],
                    into issues: inout [CoreKit.ValidationIssue]
                ) {
                    \(indented(validation, by: 4))
                }
                """)
        }
        let conformance = protocols.isEmpty ? "" : ": CoreKit.SchemaRepresentable"
        let extensionDecl: DeclSyntax = """
            extension \(type.trimmed)\(raw: conformance) {
                \(raw: indented(members.joined(separator: "\n\n"), by: 4))
            }
            """
        return [extensionDecl.cast(ExtensionDeclSyntax.self)]
    }

    /// The `name:` argument, which names the schema in place of the type's name.
    private static func name(of node: AttributeSyntax) throws -> String? {
        guard let argument = node.arguments?.as(LabeledExprListSyntax.self)?.first(where: { $0.label?.text == "name" }) else {
            return nil
        }
        guard let name = literalValue(of: argument.expression), !name.isEmpty else {
            throw MacroError("The name must be a string literal that is not empty")
        }
        return name
    }

    /// The `tag:` argument, which names both the JSON key and the generated property.
    private static func tag(of node: AttributeSyntax) throws -> String? {
        guard let argument = node.arguments?.as(LabeledExprListSyntax.self)?.first(where: { $0.label?.text == "tag" }) else {
            return nil
        }
        guard let tag = literalValue(of: argument.expression), tag.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil else {
            throw MacroError("The tag must be a string literal that is a valid Swift identifier")
        }
        return tag
    }

    private static func objectSchema(_ structDecl: StructDeclSyntax, name: String) throws -> String {
        let properties = try structDecl.storedProperties.map { property in
            guard let type = property.type else {
                throw MacroError("@Schema needs an explicit type for '\(property.name)'")
            }
            let key = stringLiteral(Naming.snakeCase(property.name))
            // Only passed when given, so plain properties stay short.
            let rules = property.rules
            let rulesArgument = rules.isEmpty ? "" : ", rules: [\(rules.joined(separator: ", "))]"
            // The initial value is what the property has when the JSON leaves it out.
            let defaultArgument = property.initializer.map { ", default: CoreKit.JSONValue.schemaDefault(\($0) as \(type))" } ?? ""
            return
                ".init(\(key), \(type).self, description: \(optionalStringLiteral(property.documentation))\(rulesArgument)\(defaultArgument)),"
        }
        return """
            .object(
                name: \(stringLiteral(name)),
                description: \(optionalStringLiteral(structDecl.leadingTrivia.documentation)),
                properties: [
                    \(indented(properties.joined(separator: "\n"), by: 8))
                ]
            )
            """
    }

    /// `init(from:)` for a `Decodable` struct with a `var` that has an initial value; `nil` for every other struct,
    /// which keeps Swift's own decoding. It goes into the extension, since an initializer in the struct's body would
    /// take away the memberwise one.
    private static func decodingInitializer(_ structDecl: StructDeclSyntax) -> String? {
        let isDecodable =
            structDecl.inheritanceClause?.inheritedTypes.contains {
                ["Codable", "Decodable"].contains($0.type.trimmedDescription.split(separator: ".").last)
            } ?? false
        let writesItsOwn = structDecl.memberBlock.members.contains {
            $0.decl.as(InitializerDeclSyntax.self)?.signature.parameterClause.parameters.first?.firstName.text == "from"
        }
        let properties = structDecl.storedProperties
        guard isDecodable, !writesItsOwn, properties.contains(where: { !$0.isLet && $0.initializer != nil }) else { return nil }

        let assignments = properties.compactMap { property -> String? in
            // A `let` keeps its initial value, as in Swift's own decoding.
            guard let type = property.type, !(property.isLet && property.initializer != nil) else { return nil }
            let key = ".\(property.identifier)"
            let fallback = property.initializer.flatMap { $0.is(NilLiteralExprSyntax.self) ? nil : "(\($0) as \(type))" }
            let value =
                if let fallback {
                    // Only a missing key gets the initial value: `null` is `nil` for an optional and an error otherwise.
                    "container.contains(\(key)) ? try container.decode(\(type).self, forKey: \(key)) : \(fallback)"
                } else if let wrapped = type.optionalWrapped {
                    "try container.decodeIfPresent(\(wrapped).self, forKey: \(key))"
                } else {
                    "try container.decode(\(type).self, forKey: \(key))"
                }
            return "self.\(property.identifier) = \(value)"
        }
        return """
            public init(from decoder: any Swift.Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                \(indented(assignments.joined(separator: "\n"), by: 4))
            }
            """
    }

    /// The statements of `validate`; `nil` without stored properties, which leaves the protocol's default.
    private static func objectValidation(_ structDecl: StructDeclSyntax) -> String? {
        let properties = structDecl.storedProperties
        if properties.isEmpty { return nil }
        return properties.map { property in
            let key = stringLiteral(Naming.snakeCase(property.name))
            let rules = property.rules.joined(separator: ", ")
            // `self.`, since a property may be named like one of the parameters.
            return "self.\(property.identifier).validate([\(rules)], at: path + [.key(\(key))], into: &issues)"
        }.joined(separator: "\n")
    }
}
