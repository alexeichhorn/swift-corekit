import CoreKit
import Foundation
import Testing

enum TestMode: String, EnvValue {
    case oneShot = "one_shot"
    case agent
}

/// Compiles the `@EnvConfig` expansion against the real `EnvReader`.
@EnvConfig
struct TestEnv {
    var corekitTestDatabaseURL: String
    @Range(1...) var corekitTestConcurrency: Int = 4
    var corekitTestUsernames: [String] = []
    var corekitTestMode: TestMode = .oneShot
    var corekitTestAPIKey: Secret?
}

@Test func envReaderPrefersProcessEnvironmentOverDotEnv() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "corekit-\(UUID()).env").path
    try """
    # comment
    HOME=/from/dotenv
    export COREKIT_TEST_PORT=8080 # trailing comment
    COREKIT_TEST_GREETING="hello # not a comment"
    """.write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let reader = EnvReader(dotEnvPath: path)
    #expect(reader.required("HOME") as String == ProcessInfo.processInfo.environment["HOME"])
    #expect(reader.value("COREKIT_TEST_PORT", default: 0) == 8080)
    #expect(reader.optional("COREKIT_TEST_GREETING") == "hello # not a comment")
    #expect(reader.optional("COREKIT_TEST_MISSING") as Secret? == nil)
}

@Test func envReaderTrimsValuesAndTreatsEmptyOnesAsMissing() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "corekit-\(UUID()).env").path
    try """
    COREKIT_TEST_NAME="  padded  "
    COREKIT_TEST_EMPTY="   "
    COREKIT_TEST_LIST= a, b ,,c
    COREKIT_TEST_SEPARATORS=" , "
    COREKIT_TEST_MODE=one_shot
    """.write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let reader = EnvReader(dotEnvPath: path)
    #expect(reader.required("COREKIT_TEST_NAME") as String == "padded")
    #expect(reader.optional("COREKIT_TEST_EMPTY") as String? == nil)
    #expect(reader.value("COREKIT_TEST_EMPTY", default: 4) == 4)
    #expect(reader.required("COREKIT_TEST_LIST") as [String] == ["a", "b", "c"])
    #expect(reader.optional("COREKIT_TEST_SEPARATORS") as [String]? == nil)
    #expect(reader.required("COREKIT_TEST_MODE") as TestMode == .oneShot)
    #expect(reader.checked(reader.value("COREKIT_TEST_EMPTY", default: 4), [.minimum(1)], for: "COREKIT_TEST_EMPTY") == 4)
}

/// `load()` stops the process, so each failure runs in a child process.
@Test func loadStopsWithAMessageNamingTheVariable() async {
    let empty = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setenv("COREKIT_TEST_DATABASE_URL", "  ", 1)
        _ = TestEnv.load()
    }
    #expect(message(empty).contains("Missing required environment variables: COREKIT_TEST_DATABASE_URL"))

    let outOfRange = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setenv("COREKIT_TEST_DATABASE_URL", "postgres://localhost/app", 1)
        setenv("COREKIT_TEST_CONCURRENCY", "0", 1)
        _ = TestEnv.load()
    }
    #expect(message(outOfRange).contains("Invalid value for environment variable COREKIT_TEST_CONCURRENCY: must be at least 1"))

    let unknown = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setenv("COREKIT_TEST_DATABASE_URL", "postgres://localhost/app", 1)
        setenv("COREKIT_TEST_MODE", "two_shot", 1)
        _ = TestEnv.load()
    }
    #expect(message(unknown).contains("Invalid value for environment variable COREKIT_TEST_MODE: unknown value 'two_shot'"))
}

private func message(_ result: ExitTest.Result?) -> String {
    String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
}

@Test func envReaderReadsBoolsAndDoubles() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "corekit-\(UUID()).env").path
    try """
    COREKIT_TEST_TRUE=true
    COREKIT_TEST_YES=yes
    COREKIT_TEST_NO=no
    COREKIT_TEST_ONE=1
    COREKIT_TEST_ZERO=0
    COREKIT_TEST_RATIO=0.25
    """.write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let reader = EnvReader(dotEnvPath: path)
    #expect(reader.required("COREKIT_TEST_TRUE") as Bool)
    #expect(reader.required("COREKIT_TEST_YES") as Bool)
    #expect(!(reader.required("COREKIT_TEST_NO") as Bool))
    #expect(reader.required("COREKIT_TEST_ONE") as Bool)
    #expect(!(reader.required("COREKIT_TEST_ZERO") as Bool))
    #expect(reader.required("COREKIT_TEST_RATIO") as Double == 0.25)
}

@EnvConfig
struct ServiceEnv {
    var corekitTestServiceURL: String
    var corekitTestServiceHosts: [String]
}

/// One message names every missing variable; a list of nothing but separators is missing too.
@Test func loadNamesEveryMissingVariable() async {
    let bothMissing = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        _ = ServiceEnv.load()
    }
    #expect(
        message(bothMissing).contains(
            "Missing required environment variables: COREKIT_TEST_SERVICE_URL, COREKIT_TEST_SERVICE_HOSTS"))

    let noHosts = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setenv("COREKIT_TEST_SERVICE_URL", "https://example.com", 1)
        setenv("COREKIT_TEST_SERVICE_HOSTS", " , ", 1)
        _ = ServiceEnv.load()
    }
    #expect(message(noHosts).contains("Missing required environment variable: COREKIT_TEST_SERVICE_HOSTS"))
}

/// A comment after a quoted value is not part of the value, and the quotes go either way.
@Test func envReaderDropsACommentAfterAQuotedValue() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "corekit-\(UUID()).env").path
    try """
    COREKIT_TEST_DOUBLE="a b" # note
    COREKIT_TEST_SINGLE='c' # don't
    COREKIT_TEST_HASH="d # e"
    COREKIT_TEST_INNER="say "hi""
    """.write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let reader = EnvReader(dotEnvPath: path)
    #expect(reader.required("COREKIT_TEST_DOUBLE") as String == "a b")
    #expect(reader.required("COREKIT_TEST_SINGLE") as String == "c")
    #expect(reader.required("COREKIT_TEST_HASH") as String == "d # e")
    #expect(reader.required("COREKIT_TEST_INNER") as String == #"say "hi""#)
}
