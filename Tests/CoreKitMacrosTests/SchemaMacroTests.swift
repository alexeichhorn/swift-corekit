import CoreKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros = [
    "Schema": MacroSpec(type: SchemaMacro.self, conformances: ["SchemaRepresentable"]),
    "Length": MacroSpec(type: ConstraintMacro.self),
    "Range": MacroSpec(type: ConstraintMacro.self),
    "Pattern": MacroSpec(type: ConstraintMacro.self),
    "Tag": MacroSpec(type: UnionCaseMacro.self),
    "UnknownTag": MacroSpec(type: UnionCaseMacro.self),
]

@Test func structSchemaUsesSnakeCaseKeysAndDocComments() {
    assertExpansion(
        """
        /// An order to create.
        @Schema
        struct CreateOrderInput: Codable {
            /// Shown on the receipt.
            let title: String
            let dueAt: Date?
            var userID: Int64
            var tags: [String: [Int]]
            var isDone: Bool { false }
        }
        """,
        expandedSource: """
            /// An order to create.
            struct CreateOrderInput: Codable {
                /// Shown on the receipt.
                let title: String
                let dueAt: Date?
                var userID: Int64
                var tags: [String: [Int]]
                var isDone: Bool { false }

                enum CodingKeys: String, CodingKey {
                    case title
                    case dueAt = "due_at"
                    case userID = "user_id"
                    case tags
                }
            }

            extension CreateOrderInput: CoreKit.SchemaRepresentable {
                public static var jsonSchema: CoreKit.JSONSchema {
                    .object(
                        name: "CreateOrderInput",
                        description: "An order to create.",
                        properties: [
                            .init("title", String.self, description: "Shown on the receipt."),
                            .init("due_at", Date?.self, description: nil),
                            .init("user_id", Int64.self, description: nil),
                            .init("tags", [String: [Int]].self, description: nil),
                        ]
                    )
                }

                public func validate(
                    _ rules: [CoreKit.ValidationRule],
                    at path: [CoreKit.ValidationIssue.PathElement],
                    into issues: inout [CoreKit.ValidationIssue]
                ) {
                    self.title.validate([], at: path + [.key("title")], into: &issues)
                    self.dueAt.validate([], at: path + [.key("due_at")], into: &issues)
                    self.userID.validate([], at: path + [.key("user_id")], into: &issues)
                    self.tags.validate([], at: path + [.key("tags")], into: &issues)
                }
            }
            """,
        macros: macros
    )
}

@Test func enumSchemaListsRawValues() {
    assertExpansion(
        """
        @Schema
        enum OrderActivityKind: String, Codable {
            case created, completed
            case inProgress = "in_progress"
        }
        """,
        expandedSource: """
            enum OrderActivityKind: String, Codable {
                case created, completed
                case inProgress = "in_progress"
            }

            extension OrderActivityKind: CoreKit.SchemaRepresentable {
                public static var jsonSchema: CoreKit.JSONSchema {
                    .enumeration(
                        name: "OrderActivityKind",
                        description: nil,
                        values: [.string(Self.created.rawValue), .string(Self.completed.rawValue), .string(Self.inProgress.rawValue)]
                    )
                }
            }
            """,
        macros: macros
    )
}

@Test func taggedEnumEncodesPayloadWithTag() {
    assertExpansion(
        """
        struct Page {
            /// One Page section.
            @Schema(tag: "kind")
            public enum Section: Codable {
                case linkList(LinkListSection)
                case pullQuote(PullQuoteSection)
            }
        }
        """,
        expandedSource: #"""
            struct Page {
                /// One Page section.
                public enum Section: Codable {
                    case linkList(LinkListSection)
                    case pullQuote(PullQuoteSection)

                    enum CodingKeys: String, CodingKey {
                        case tag = "kind"
                    }

                    /// The case's `kind` value on the wire.
                    public var kind: String {
                        switch self {
                        case .linkList:
                            "link_list"
                        case .pullQuote:
                            "pull_quote"
                        }
                    }

                    public init(from decoder: any Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        switch try container.decode(String.self, forKey: .tag) {
                        case "link_list":
                            self = .linkList(try LinkListSection(from: decoder))
                        case "pull_quote":
                            self = .pullQuote(try PullQuoteSection(from: decoder))
                        case let unknown:
                            throw DecodingError.dataCorruptedError(forKey: .tag, in: container, debugDescription: "Unknown kind '\(unknown)'")
                        }
                    }

                    public func encode(to encoder: any Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(kind, forKey: .tag)
                        switch self {
                        case .linkList(let payload):
                            try payload.encode(to: encoder)
                        case .pullQuote(let payload):
                            try payload.encode(to: encoder)
                        }
                    }
                }
            }

            extension Page.Section: CoreKit.SchemaRepresentable {
                public static var jsonSchema: CoreKit.JSONSchema {
                    .taggedUnion(
                        name: "Page.Section",
                        description: "One Page section.",
                        tag: "kind",
                        variants: [
                            ("link_list", .associatedValue(of: Self.linkList)),
                            ("pull_quote", .associatedValue(of: Self.pullQuote)),
                        ]
                    )
                }

                public func validate(
                    _ rules: [CoreKit.ValidationRule],
                    at path: [CoreKit.ValidationIssue.PathElement],
                    into issues: inout [CoreKit.ValidationIssue]
                ) {
                    switch self {
                    case .linkList(let value):
                        value.validate(rules, at: path, into: &issues)
                    case .pullQuote(let value):
                        value.validate(rules, at: path, into: &issues)
                    }
                }
            }
            """#,
        macros: macros
    )
}

@Test func untaggedEnumTriesCasesInOrder() {
    assertExpansion(
        """
        @Schema
        enum Content: Codable {
            case text(String)
            case items([Item])
        }
        """,
        expandedSource: """
            enum Content: Codable {
                case text(String)
                case items([Item])

                init(from decoder: any Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let value = try? container.decode(String.self) {
                        self = .text(value)
                    } else {
                        self = .items(try container.decode([Item].self))
                    }
                }

                func encode(to encoder: any Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .text(let value):
                        try container.encode(value)
                    case .items(let value):
                        try container.encode(value)
                    }
                }
            }

            extension Content: CoreKit.SchemaRepresentable {
                public static var jsonSchema: CoreKit.JSONSchema {
                    .union(
                        name: "Content",
                        description: nil,
                        variants: [
                            .associatedValue(of: Self.text),
                            .associatedValue(of: Self.items),
                        ]
                    )
                }

                public func validate(
                    _ rules: [CoreKit.ValidationRule],
                    at path: [CoreKit.ValidationIssue.PathElement],
                    into issues: inout [CoreKit.ValidationIssue]
                ) {
                    switch self {
                    case .text(let value):
                        value.validate(rules, at: path, into: &issues)
                    case .items(let value):
                        value.validate(rules, at: path, into: &issues)
                    }
                }
            }
            """,
        macros: macros
    )
}

@Test func taggedEnumWithUnknownTagCaseOnlyDecodes() {
    assertExpansion(
        """
        @Schema(tag: "type")
        enum Event: Decodable {
            @Tag("order.created") case orderCreated(Order)
            case refund(Refund)
            @UnknownTag case other
        }
        """,
        expandedSource: """
            enum Event: Decodable {
                case orderCreated(Order)
                case refund(Refund)
                case other

                enum CodingKeys: String, CodingKey {
                    case tag = "type"
                }

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    switch try container.decode(String.self, forKey: .tag) {
                    case "order.created":
                        self = .orderCreated(try Order(from: decoder))
                    case "refund":
                        self = .refund(try Refund(from: decoder))
                    default:
                        self = .other
                    }
                }
            }

            extension Event: CoreKit.SchemaRepresentable {
                public static var jsonSchema: CoreKit.JSONSchema {
                    .taggedUnion(
                        name: "Event",
                        description: nil,
                        tag: "type",
                        variants: [
                            ("order.created", .associatedValue(of: Self.orderCreated)),
                            ("refund", .associatedValue(of: Self.refund)),
                        ]
                    )
                }

                public func validate(
                    _ rules: [CoreKit.ValidationRule],
                    at path: [CoreKit.ValidationIssue.PathElement],
                    into issues: inout [CoreKit.ValidationIssue]
                ) {
                    switch self {
                    case .orderCreated(let value):
                        value.validate(rules, at: path, into: &issues)
                    case .refund(let value):
                        value.validate(rules, at: path, into: &issues)
                    case .other:
                        break
                    }
                }
            }
            """,
        macros: macros
    )
}

@Test func tagValueInterpretsEscapes() {
    assertExpansion(
        """
        @Schema(tag: "type")
        enum Event: Decodable {
            @Tag("order\\u{2E}created") case orderCreated(Order)
            @UnknownTag case other
        }
        """,
        expandedSource: """
            enum Event: Decodable {
                case orderCreated(Order)
                case other

                enum CodingKeys: String, CodingKey {
                    case tag = "type"
                }

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    switch try container.decode(String.self, forKey: .tag) {
                    case "order.created":
                        self = .orderCreated(try Order(from: decoder))
                    default:
                        self = .other
                    }
                }
            }

            extension Event: CoreKit.SchemaRepresentable {
                public static var jsonSchema: CoreKit.JSONSchema {
                    .taggedUnion(
                        name: "Event",
                        description: nil,
                        tag: "type",
                        variants: [
                            ("order.created", .associatedValue(of: Self.orderCreated)),
                        ]
                    )
                }

                public func validate(
                    _ rules: [CoreKit.ValidationRule],
                    at path: [CoreKit.ValidationIssue.PathElement],
                    into issues: inout [CoreKit.ValidationIssue]
                ) {
                    switch self {
                    case .orderCreated(let value):
                        value.validate(rules, at: path, into: &issues)
                    case .other:
                        break
                    }
                }
            }
            """,
        macros: macros
    )
}

@Test func taggedEnumRejectsEncodingAnUnknownTagCase() {
    assertExpansion(
        """
        @Schema(tag: "type")
        enum Event: Codable {
            case refund(Refund)
            @UnknownTag case other
        }
        """,
        expandedSource: """
            enum Event: Codable {
                case refund(Refund)
                case other
            }
            """,
        diagnostics: [
            DiagnosticSpec(
                message: "A @Schema(tag:) enum with an @UnknownTag case can only be Decodable, since that case has no tag to encode",
                line: 1,
                column: 1
            )
        ],
        macros: macros
    )
}

@Test func taggedEnumRejectsLabeledAssociatedValues() {
    assertExpansion(
        """
        @Schema(tag: "kind")
        enum Section: Codable {
            case links(items: [Link])
        }
        """,
        expandedSource: """
            enum Section: Codable {
                case links(items: [Link])
            }
            """,
        diagnostics: [
            DiagnosticSpec(
                message:
                    "Every case of a @Schema(tag:) enum needs exactly one unlabeled associated value, a @Schema struct; 'links' doesn't",
                line: 1,
                column: 1
            )
        ],
        macros: macros
    )
}

@Test func constraintsBecomeRulesOfTheSchemaAndOfValidation() {
    assertExpansion(
        #"""
        @Schema
        struct ProductQuery: Codable {
            @Length(min: 3, max: 200) var query: String
            @Range(1...20) var pageSize: Int
            @Pattern("^[a-z]{2}$") var region: String?
            @Length(max: 5) @Pattern("^[a-z]+$") var tags: [String]
            @Range(1...5) var ratings: [Int]? = nil
            var limit: Int = 10
        }
        """#,
        expandedSource: #"""
            struct ProductQuery: Codable {
                var query: String
                var pageSize: Int
                var region: String?
                var tags: [String]
                var ratings: [Int]? = nil
                var limit: Int = 10

                enum CodingKeys: String, CodingKey {
                    case query
                    case pageSize = "page_size"
                    case region
                    case tags
                    case ratings
                    case limit
                }
            }

            extension ProductQuery: CoreKit.SchemaRepresentable {
                public init(from decoder: any Swift.Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.query = try container.decode(String.self, forKey: .query)
                    self.pageSize = try container.decode(Int.self, forKey: .pageSize)
                    self.region = try container.decodeIfPresent(String.self, forKey: .region)
                    self.tags = try container.decode([String].self, forKey: .tags)
                    self.ratings = try container.decodeIfPresent([Int].self, forKey: .ratings)
                    self.limit = container.contains(.limit) ? try container.decode(Int.self, forKey: .limit) : (10 as Int)
                }

                public static var jsonSchema: CoreKit.JSONSchema {
                    .object(
                        name: "ProductQuery",
                        description: nil,
                        properties: [
                            .init("query", String.self, description: nil, rules: [.minLength(3), .maxLength(200)]),
                            .init("page_size", Int.self, description: nil, rules: [.minimum(1), .maximum(20)]),
                            .init("region", String?.self, description: nil, rules: [.pattern("^[a-z]{2}$")]),
                            .init("tags", [String].self, description: nil, rules: [.maxItems(5), .items([.pattern("^[a-z]+$")])]),
                            .init("ratings", [Int]?.self, description: nil, rules: [.items([.minimum(1), .maximum(5)])], default: CoreKit.JSONValue.schemaDefault(nil as [Int]?)),
                            .init("limit", Int.self, description: nil, default: CoreKit.JSONValue.schemaDefault(10 as Int)),
                        ]
                    )
                }

                public func validate(
                    _ rules: [CoreKit.ValidationRule],
                    at path: [CoreKit.ValidationIssue.PathElement],
                    into issues: inout [CoreKit.ValidationIssue]
                ) {
                    self.query.validate([.minLength(3), .maxLength(200)], at: path + [.key("query")], into: &issues)
                    self.pageSize.validate([.minimum(1), .maximum(20)], at: path + [.key("page_size")], into: &issues)
                    self.region.validate([.pattern("^[a-z]{2}$")], at: path + [.key("region")], into: &issues)
                    self.tags.validate([.maxItems(5), .items([.pattern("^[a-z]+$")])], at: path + [.key("tags")], into: &issues)
                    self.ratings.validate([.items([.minimum(1), .maximum(5)])], at: path + [.key("ratings")], into: &issues)
                    self.limit.validate([], at: path + [.key("limit")], into: &issues)
                }
            }
            """#,
        macros: macros
    )
}

@Test func constraintsRejectUnsupportedTypesAndMalformedArguments() {
    assertExpansion(
        """
        struct ProductQuery {
            @Length(max: 5) var pageSize: Int
            @Range(1...20) var query: String
            @Pattern("^[a-z]{2}$") var tags: [Int]
            @Length(min: 5, max: 3) var region: String
            @Range(1..<20) var limit: Int
            @Pattern("[a-z") var language: String
            @Range(...9_007_199_254_740_992) var total: Int64
        }
        """,
        expandedSource: """
            struct ProductQuery {
                var pageSize: Int
                var query: String
                var tags: [Int]
                var region: String
                var limit: Int
                var language: String
                var total: Int64
            }
            """,
        diagnostics: [
            DiagnosticSpec(message: "@Length applies to String and array properties, not 'Int'", line: 2, column: 5),
            DiagnosticSpec(
                message: "@Range applies to integer and floating-point properties and arrays of them, not 'String'", line: 3, column: 5),
            DiagnosticSpec(message: "@Pattern applies to String properties and arrays of them, not '[Int]'", line: 4, column: 5),
            DiagnosticSpec(
                message: "@Length takes integer literals with min at most max: @Length(min: 3, max: 200)", line: 5, column: 5),
            DiagnosticSpec(
                message: "@Range takes inclusive bounds of number literals: @Range(1...20), @Range(1...) or @Range(...20)",
                line: 6,
                column: 5
            ),
            DiagnosticSpec(message: "@Pattern needs a valid regular expression: expected ']'", line: 7, column: 5),
            DiagnosticSpec(
                message: "@Range bounds of an integer property must lie between -9007199254740991 and 9007199254740991", line: 8,
                column: 5),
        ],
        macros: macros
    )
}
