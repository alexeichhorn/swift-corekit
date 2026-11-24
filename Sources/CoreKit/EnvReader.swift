public import Configuration
import Foundation

/// Reads environment variables for `@EnvConfig`; process variables override the working directory's `.env`.
///
/// Values are trimmed, and a variable that is empty after trimming counts as missing. Missing or invalid values are
/// configuration errors, so they stop the process with a message naming the keys.
public struct EnvReader {
    private let reader: ConfigReader

    public init(dotEnvPath: String = ".env") {
        let dotEnv = (try? String(contentsOfFile: dotEnvPath, encoding: .utf8)).map(Self.parseDotEnv) ?? [:]
        reader = ConfigReader(providers: [
            EnvironmentVariablesProvider(environmentVariables: Self.nonEmpty(ProcessInfo.processInfo.environment)),
            EnvironmentVariablesProvider(environmentVariables: Self.nonEmpty(dotEnv)),
        ])
    }

    /// Stops the process listing every key in `keys` that has no value.
    public func checkRequired(_ keys: [String]) {
        let missingKeys = keys.filter { reader.string(forKey: ConfigKey($0)) == nil }
        if !missingKeys.isEmpty {
            fatalError("Missing required environment variables: \(missingKeys.joined(separator: ", "))")
        }
    }

    public func required<Value: EnvValue>(_ key: String) -> Value {
        guard let value: Value = optional(key) else { fatalError("Missing required environment variable: \(key)") }
        return value
    }

    public func optional<Value: EnvValue>(_ key: String) -> Value? {
        guard reader.string(forKey: ConfigKey(key)) != nil else { return nil }
        do {
            let value = try Value.read(ConfigKey(key), from: reader)
            // A list of nothing but separators has no entries, so it counts as missing too.
            if let list = value as? [String], list.isEmpty { return nil }
            return value
        } catch {
            fatalError("Invalid value for environment variable \(key): \(error)")
        }
    }

    public func value<Value: EnvValue>(_ key: String, default defaultValue: Value) -> Value {
        optional(key) ?? defaultValue
    }

    /// Returns `value`, or stops the process when it violates one of `rules`; `key` names the variable in the message.
    public func checked<Value: SchemaRepresentable>(_ value: Value, _ rules: [ValidationRule], for key: String) -> Value {
        var issues: [ValidationIssue] = []
        value.validate(rules, at: [], into: &issues)
        if let issue = issues.first { fatalError("Invalid value for environment variable \(key): \(issue.rule)") }
        return value
    }

    /// The variables with trimmed values, without the empty ones.
    private static func nonEmpty(_ variables: [String: String]) -> [String: String] {
        variables.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.value.isEmpty }
    }

    /// Parses `KEY=value` lines; supports `#` comments, `export` prefixes, and quoted values.
    static func parseDotEnv(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line.removeFirst("export ".count) }
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'", value.count >= 2, value.last == quote {
                value = String(value.dropFirst().dropLast())
            } else if let comment = value.range(of: " #") {
                value = value[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            values[key] = value
        }
        return values
    }
}

/// A type `@EnvConfig` properties can have. A `String` raw-value enum only has to declare the conformance.
public protocol EnvValue {
    static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> Self
}

extension EnvValue where Self: RawRepresentable, RawValue == String {
    public static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> Self {
        let rawValue = try reader.requiredString(forKey: key)
        guard let value = Self(rawValue: rawValue) else { throw UnknownEnvValue(rawValue: rawValue) }
        return value
    }
}

struct UnknownEnvValue: Error, CustomStringConvertible {
    let rawValue: String

    var description: String { "unknown value '\(rawValue)'" }
}

extension String: EnvValue {
    public static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> String { try reader.requiredString(forKey: key) }
}

extension Int: EnvValue {
    public static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> Int { try reader.requiredInt(forKey: key) }
}

extension Double: EnvValue {
    public static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> Double { try reader.requiredDouble(forKey: key) }
}

/// Accepts `true`/`false`, `yes`/`no`, and `1`/`0`.
extension Bool: EnvValue {
    public static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> Bool { try reader.requiredBool(forKey: key) }
}

extension Secret: EnvValue {
    public static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> Secret {
        Secret(try reader.requiredString(forKey: key, isSecret: true))
    }
}

/// A comma-separated list; entries are trimmed and empty ones dropped.
extension Array: EnvValue where Element == String {
    public static func read(_ key: ConfigKey, from reader: ConfigReader) throws -> [String] {
        try reader.requiredStringArray(forKey: key).filter { !$0.isEmpty }
    }
}
