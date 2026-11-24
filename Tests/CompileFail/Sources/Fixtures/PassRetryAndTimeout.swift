import CoreKit

final class Draft {
    var title = ""
}

// Without a timeout the body runs in the caller's task, so it may capture what isn't Sendable.
@Retry(maxRetries: 1)
func publish(_ draft: Draft) async throws -> String { draft.title }

@Timeout(.seconds(1))
func publishedTitle(_ title: String) async throws -> String { title }
