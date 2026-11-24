import CoreKitMacros
import SwiftSyntaxMacroExpansion
import Testing

@Test func envConfigReadsScreamingSnakeCaseKeys() {
    assertExpansion(
        """
        @EnvConfig
        public struct Env {
            var databaseURL: String
            var appEnv: String = "local"
            var port: Int = 8000
            var openaiAPIKey: Secret?
            var devMode: Bool = false
            @Range(1...) var concurrency: Int = 4
            let version = "1"
        }
        """,
        expandedSource: """
            public struct Env {
                var databaseURL: String
                var appEnv: String = "local"
                var port: Int = 8000
                var openaiAPIKey: Secret?
                var devMode: Bool = false
                var concurrency: Int = 4
                let version = "1"
            }

            extension Env: Sendable {
                /// Reads the configuration from the process environment and the working directory's `.env`.
                public static func load() -> Self {
                    let reader = CoreKit.EnvReader()
                    reader.checkRequired(["DATABASE_URL"])
                    return Self(
                        databaseURL: reader.required("DATABASE_URL"),
                        appEnv: reader.value("APP_ENV", default: "local"),
                        port: reader.value("PORT", default: 8000),
                        openaiAPIKey: reader.optional("OPENAI_API_KEY"),
                        devMode: reader.value("DEV_MODE", default: false),
                        concurrency: reader.checked(reader.value("CONCURRENCY", default: 4), [.minimum(1)], for: "CONCURRENCY")
                    )
                }
            }
            """,
        macros: [
            "EnvConfig": MacroSpec(type: EnvConfigMacro.self, conformances: ["Sendable"]),
            "Range": MacroSpec(type: ConstraintMacro.self),
        ]
    )
}

/// An acronym run ends before a capitalized word, so two acronyms in a row read as one; a plural `s` stays with its
/// acronym.
@Test func envConfigEndsAnAcronymRunBeforeACapitalizedWord() {
    assertExpansion(
        """
        @EnvConfig
        struct Env {
            var openAIAPIKey: Secret?
            var allowedHostIDs: [String] = []
        }
        """,
        expandedSource: """
            struct Env {
                var openAIAPIKey: Secret?
                var allowedHostIDs: [String] = []
            }

            extension Env: Sendable {
                /// Reads the configuration from the process environment and the working directory's `.env`.
                static func load() -> Self {
                    let reader = CoreKit.EnvReader()
                    return Self(
                        openAIAPIKey: reader.optional("OPEN_AIAPI_KEY"),
                        allowedHostIDs: reader.value("ALLOWED_HOST_IDS", default: [])
                    )
                }
            }
            """,
        macros: ["EnvConfig": MacroSpec(type: EnvConfigMacro.self, conformances: ["Sendable"])]
    )
}
