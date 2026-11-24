/// Splits Swift identifiers into words: `openaiAPIKey` → `openai`, `API`, `Key`.
///
/// An uppercase letter starts a new word after a lowercase letter or digit, and ends an acronym run when a
/// lowercase letter follows it (`APIKey` → `API`, `Key`). A plural `s` stays with its acronym (`userIDs` → `user`,
/// `IDs`), so a one-letter word before `Is`, `As` or `Us` joins it too (`planBIsActive` → `plan`, `BIs`, `Active`).
enum Naming {
    static func snakeCase(_ identifier: String) -> String {
        words(identifier).map { $0.lowercased() }.joined(separator: "_")
    }

    static func screamingSnakeCase(_ identifier: String) -> String {
        words(identifier).map { $0.uppercased() }.joined(separator: "_")
    }

    private static func words(_ identifier: String) -> [String] {
        let characters = Array(identifier)
        var words: [String] = []
        var word = ""
        for (index, character) in characters.enumerated() {
            if character == "_" {
                if !word.isEmpty { words.append(word) }
                word = ""
                continue
            }
            if character.isUppercase, let previous = word.last {
                let rest = characters[(index + 1)...]
                let isPlural = rest.first == "s" && rest.dropFirst().first?.isLowercase != true
                let endsAcronym = previous.isUppercase && rest.first?.isLowercase == true && !isPlural
                if previous.isLowercase || previous.isNumber || endsAcronym {
                    words.append(word)
                    word = ""
                }
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words
    }
}
