import SwiftSyntax

/// The shape of a `@Schema` enum and the code generated for it.
///
/// A union's cases each wrap one value. Untagged, a value is encoded as its payload; tagged, as the payload struct's
/// object plus the tag key set to the case's tag value.
enum SchemaEnum {
    case rawValues(valueCase: String, caseIdentifiers: [String])
    case union([UnionCase])
    /// `unknownCase` is the `@UnknownTag` case, which has no payload and takes every tag that no other case has.
    case taggedUnion(tag: String, [UnionCase], unknownCase: String?)

    struct UnionCase {
        /// The case name as written, including backticks.
        let identifier: String
        let payloadType: TypeSyntax
        /// The case's `@Tag`, or else its snake_case name. Unused in an untagged union.
        let tagValue: String
    }

    init(_ enumDecl: EnumDeclSyntax, tag: String?) throws {
        let caseDecls = enumDecl.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
        let elements = caseDecls.flatMap(\.elements)
        let rawType = enumDecl.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription
        let hasRawValues = rawType == "String" || rawType == "Int"
        if let tag {
            if hasRawValues { throw MacroError("@Schema(tag:) enums can't have raw values") }
            self = try Self.taggedUnion(tag: tag, caseDecls, of: enumDecl)
            return
        }
        if caseDecls.contains(where: { !$0.tagMarkers.isEmpty }) {
            throw MacroError("@Tag and @UnknownTag apply to the cases of a @Schema(tag:) enum")
        }
        if elements.contains(where: { $0.parameterClause != nil }) {
            if hasRawValues { throw MacroError("@Schema enums can't mix raw values and associated values") }
            self = .union(try elements.map { try Self.unionCase($0, tagged: false) })
        } else {
            let valueCase: String
            switch rawType {
            case "String": valueCase = "string"
            case "Int": valueCase = "int"
            default: throw MacroError("@Schema enums need a String or Int raw value, or one associated value per case")
            }
            self = .rawValues(valueCase: valueCase, caseIdentifiers: elements.map(\.name.text))
        }
    }

    private static func taggedUnion(tag: String, _ caseDecls: [EnumCaseDeclSyntax], of enumDecl: EnumDeclSyntax) throws -> SchemaEnum {
        var cases: [UnionCase] = []
        var unknownCases: [String] = []
        for caseDecl in caseDecls {
            let markers = caseDecl.tagMarkers
            if markers.contains(where: { $0.name == "UnknownTag" }) {
                unknownCases += caseDecl.elements.map(\.name.text)
                continue
            }
            // A malformed `@Tag` reports itself and leaves the case its own name.
            let customTag = caseDecl.elements.count == 1 ? markers.first.flatMap { try? UnionCaseMacro.tagValue(of: $0) } : nil
            cases += try caseDecl.elements.map { try unionCase($0, tagged: true, tagValue: customTag) }
        }

        if unknownCases.count > 1 {
            throw MacroError("A @Schema(tag:) enum can have only one @UnknownTag case")
        }
        let tagValues = cases.map(\.tagValue)
        if let duplicate = tagValues.first(where: { tagValue in tagValues.count { $0 == tagValue } > 1 }) {
            throw MacroError("Two cases of the @Schema(tag:) enum have the tag '\(duplicate)'")
        }
        let isEncodable =
            enumDecl.inheritanceClause?.inheritedTypes.contains {
                ["Codable", "Encodable"].contains($0.type.trimmedDescription.split(separator: ".").last)
            } ?? false
        if !unknownCases.isEmpty, isEncodable {
            throw MacroError("A @Schema(tag:) enum with an @UnknownTag case can only be Decodable, since that case has no tag to encode")
        }
        return .taggedUnion(tag: tag, cases, unknownCase: unknownCases.first)
    }

    private static func unionCase(_ element: EnumCaseElementSyntax, tagged: Bool, tagValue: String? = nil) throws -> UnionCase {
        let parameters = element.parameterClause?.parameters
        guard let parameter = parameters?.first, parameters?.count == 1, parameter.firstName == nil,
            !tagged || parameter.type.isNominal
        else {
            let requirement =
                tagged
                ? "@Schema(tag:) enum needs exactly one unlabeled associated value, a @Schema struct"
                : "@Schema union enum needs exactly one unlabeled associated value"
            throw MacroError("Every case of a \(requirement); '\(element.name.text)' doesn't")
        }
        let identifier = element.name.text
        return UnionCase(
            identifier: identifier,
            payloadType: parameter.type.trimmed,
            tagValue: tagValue ?? Naming.snakeCase(identifier.filter { $0 != "`" })
        )
    }

    /// `Codable` for unions, plus the tag property for tagged unions; nothing for raw-value enums.
    func members(access: String) -> [DeclSyntax] {
        switch self {
        case .rawValues: []
        case .union(let cases): Self.unionCodable(cases, access: access)
        case .taggedUnion(let tag, let cases, let unknownCase):
            Self.taggedUnionCodable(tag: tag, cases, unknownCase: unknownCase, access: access)
        }
    }

    private static func unionCodable(_ cases: [UnionCase], access: String) -> [DeclSyntax] {
        // Every case but the last is tried silently, so a failure reports the last case's error.
        let attempts = cases.dropLast().map { unionCase in
            "if let value = try? container.decode(\(unionCase.payloadType).self) {\n    self = .\(unionCase.identifier)(value)\n} else "
        }
        let lastCase = cases[cases.count - 1]
        let lastAttempt = "self = .\(lastCase.identifier)(try container.decode(\(lastCase.payloadType).self))"
        let decode = cases.count == 1 ? lastAttempt : attempts.joined() + "{\n    \(lastAttempt)\n}"
        let encodeCases = cases.map { "case .\($0.identifier)(let value): try container.encode(value)" }
        return [
            """
            \(raw: access)init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                \(raw: indented(decode, by: 4))
            }
            """,
            """
            \(raw: access)func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                \(raw: encodeCases.joined(separator: "\n    "))
                }
            }
            """,
        ]
    }

    private static func taggedUnionCodable(tag: String, _ cases: [UnionCase], unknownCase: String?, access: String) -> [DeclSyntax] {
        let codingKeys: DeclSyntax = "enum CodingKeys: String, CodingKey {\n    case tag = \(raw: stringLiteral(tag))\n}"
        let tagCases = cases.map { "case .\($0.identifier): \(stringLiteral($0.tagValue))" }
        let decodeCases = cases.map { "case \(stringLiteral($0.tagValue)): self = .\($0.identifier)(try \($0.payloadType)(from: decoder))" }
        let encodeCases = cases.map { "case .\($0.identifier)(let payload): try payload.encode(to: encoder)" }
        if let unknownCase {
            // Only decoding: the unknown case has no tag to return or encode.
            return [
                codingKeys,
                """
                \(raw: access)init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    switch try container.decode(String.self, forKey: .tag) {
                    \(raw: decodeCases.joined(separator: "\n    "))
                    default: self = .\(raw: unknownCase)
                    }
                }
                """,
            ]
        }
        return [
            codingKeys,
            """
            /// The case's `\(raw: tag)` value on the wire.
            \(raw: access)var \(raw: tag): String {
                switch self {
                \(raw: tagCases.joined(separator: "\n    "))
                }
            }
            """,
            """
            \(raw: access)init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                switch try container.decode(String.self, forKey: .tag) {
                \(raw: decodeCases.joined(separator: "\n    "))
                case let unknown:
                    throw DecodingError.dataCorruptedError(forKey: .tag, in: container, debugDescription: "Unknown \(raw: tag) '\\(unknown)'")
                }
            }
            """,
            """
            \(raw: access)func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(\(raw: tag), forKey: .tag)
                switch self {
                \(raw: encodeCases.joined(separator: "\n    "))
                }
            }
            """,
        ]
    }

    /// The statements of `validate`, which pass on to the wrapped value; `nil` for raw-value enums.
    var validation: String? {
        switch self {
        case .rawValues: nil
        case .union(let cases):
            Self.validation(cases, unknownCase: nil)
        case .taggedUnion(_, let cases, let unknownCase):
            Self.validation(cases, unknownCase: unknownCase)
        }
    }

    private static func validation(_ cases: [UnionCase], unknownCase: String?) -> String {
        let validations = cases.map { "case .\($0.identifier)(let value): value.validate(rules, at: path, into: &issues)\n" }
        return "switch self {\n" + validations.joined() + (unknownCase.map { "case .\($0): break\n" } ?? "") + "}"
    }

    /// The `JSONSchema` expression, which lists a tagged union's known cases.
    func schema(name: String, description: String?) -> String {
        let (caseName, arguments): (String, [String])
        switch self {
        case .rawValues(let valueCase, let caseIdentifiers):
            let values = caseIdentifiers.map { ".\(valueCase)(Self.\($0).rawValue)" }
            (caseName, arguments) = ("enumeration", ["values: [\(values.joined(separator: ", "))]"])
        case .union(let cases):
            let variants = cases.map { ".associatedValue(of: Self.\($0.identifier))," }
            (caseName, arguments) = ("union", ["variants: [\n    \(variants.joined(separator: "\n    "))\n]"])
        case .taggedUnion(let tag, let cases, _):
            let variants = cases.map { "(\(stringLiteral($0.tagValue)), .associatedValue(of: Self.\($0.identifier)))," }
            (caseName, arguments) = (
                "taggedUnion", ["tag: \(stringLiteral(tag))", "variants: [\n    \(variants.joined(separator: "\n    "))\n]"]
            )
        }
        let allArguments = ["name: \(stringLiteral(name))", "description: \(optionalStringLiteral(description))"] + arguments
        return ".\(caseName)(\n    \(indented(allArguments.joined(separator: ",\n"), by: 4))\n)"
    }
}

extension EnumCaseDeclSyntax {
    /// The `@Tag` and `@UnknownTag` attributes of the case.
    fileprivate var tagMarkers: [AttributeSyntax] {
        attributes.compactMap { $0.as(AttributeSyntax.self) }.filter { ["Tag", "UnknownTag"].contains($0.name) }
    }
}

extension TypeSyntax {
    /// A plain or nested type name like `Section` or `Page.Section`, not an array, optional, or dictionary.
    fileprivate var isNominal: Bool {
        self.is(IdentifierTypeSyntax.self) || self.is(MemberTypeSyntax.self)
    }
}
