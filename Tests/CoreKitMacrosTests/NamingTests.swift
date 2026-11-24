import Testing

@testable import CoreKitMacros

@Test func snakeCaseKeepsAcronymsAndTheirPluralsTogether() {
    for (identifier, expected) in [
        ("dueAt", "due_at"),
        ("openaiAPIKey", "openai_api_key"),
        ("databaseURL", "database_url"),
        ("userIDs", "user_ids"),
        ("sourceURLs", "source_urls"),
        ("urlsToFetch", "urls_to_fetch"),
        ("failedIDsByURL", "failed_ids_by_url"),
        ("lowercaseUUIDs", "lowercase_uuids"),
        ("line2Text", "line2_text"),
        ("isSet", "is_set"),
        ("httpStatus", "http_status"),
    ] {
        #expect(Naming.snakeCase(identifier) == expected)
    }
    #expect(Naming.screamingSnakeCase("allowedHostIDs") == "ALLOWED_HOST_IDS")
}
