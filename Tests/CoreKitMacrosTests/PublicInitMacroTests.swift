import CoreKitMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Test func publicInitTakesEveryStoredPropertyInOrder() {
    assertExpansion(
        """
        @PublicInit
        public struct Upload: Sendable {
            public var name: String
            public var size: Int?
            public var tags: [String] = []
            public let onProgress: @Sendable (Int) -> Void
            public let onDone: (() -> Void)
            public let version = 1
            public static let limit = 10
            public var isEmpty: Bool { size == 0 }
        }
        """,
        expandedSource: """
            public struct Upload: Sendable {
                public var name: String
                public var size: Int?
                public var tags: [String] = []
                public let onProgress: @Sendable (Int) -> Void
                public let onDone: (() -> Void)
                public let version = 1
                public static let limit = 10
                public var isEmpty: Bool { size == 0 }

                public init(
                    name: String,
                    size: Int?,
                    tags: [String] = [],
                    onProgress: @escaping @Sendable (Int) -> Void,
                    onDone: @escaping (() -> Void)
                ) {
                    self.name = name
                    self.size = size
                    self.tags = tags
                    self.onProgress = onProgress
                    self.onDone = onDone
                }
            }
            """,
        macros: ["PublicInit": MacroSpec(type: PublicInitMacro.self)]
    )
}

@Test func publicInitWithoutPropertiesTakesNoParameters() {
    assertExpansion(
        """
        @PublicInit
        public struct Marker {}
        """,
        expandedSource: """
            public struct Marker {

                public init() {
                }
            }
            """,
        macros: ["PublicInit": MacroSpec(type: PublicInitMacro.self)]
    )
}

@Test func publicInitRejectsOtherTypesAndPropertiesWithoutAType() {
    assertExpansion(
        """
        @PublicInit
        public final class Upload {}

        @PublicInit
        public struct Order {
            public var note = ""
        }
        """,
        expandedSource: """
            public final class Upload {}
            public struct Order {
                public var note = ""
            }
            """,
        diagnostics: [
            DiagnosticSpec(message: "@PublicInit can only be applied to a struct", line: 1, column: 1),
            DiagnosticSpec(message: "@PublicInit needs a type annotation on `note`", line: 4, column: 1),
        ],
        macros: ["PublicInit": MacroSpec(type: PublicInitMacro.self)]
    )
}
