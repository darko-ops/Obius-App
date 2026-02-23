import Foundation

/// Calls the Claude Messages API for Intelligence chat
enum ClaudeService {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"

    struct Message: Codable {
        let role: String
        let content: String
    }

    // MARK: - Public

    /// Send a conversation to Claude and return the assistant reply.
    /// - Parameters:
    ///   - messages: Full conversation history (user / assistant pairs).
    ///   - noteContext: Brief summary of the user's workspace to include in the system prompt.
    static func send(
        messages: [Message],
        noteContext: String
    ) async throws -> String {
        guard let apiKey = AppConfiguration.claudeAPIKey else {
            throw ClaudeError.missingAPIKey
        }

        let systemPrompt = """
        You are the intelligence assistant inside Obius, a note-taking app. \
        Answer questions about the user's notes and help them stay organised. \
        Be concise and helpful.

        Current workspace context:
        \(noteContext)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: http.statusCode, detail: detail)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ClaudeError.unexpectedBody
        }

        return text
    }

    // MARK: - Title Generation

    /// Generate a short AI title (2-5 words) from note content.
    static func generateTitle(from content: String) async throws -> String {
        guard let apiKey = AppConfiguration.claudeAPIKey else {
            print("⚠️ [ClaudeService] API key not configured — set CLAUDE_API_KEY in Debug.xcconfig")
            throw ClaudeError.missingAPIKey
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 30,
            "system": "You are a title generator. Given note content, respond with ONLY a short title (2-5 words). No quotes, no punctuation, no explanation.",
            "messages": [["role": "user", "content": "Generate a short title for this note:\n\n\(content)"]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: http.statusCode, detail: detail)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ClaudeError.unexpectedBody
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tag Generation

    /// Generate concept tags from note content. Returns 1-5 single-word tags.
    static func generateTags(from content: String) async throws -> [String] {
        guard let apiKey = AppConfiguration.claudeAPIKey else {
            print("⚠️ [ClaudeService] API key not configured — set CLAUDE_API_KEY in Debug.xcconfig")
            throw ClaudeError.missingAPIKey
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 50,
            "system": "You are a concept tagger. Given note content, identify the key themes or concepts. Respond with ONLY a comma-separated list of 1-5 single-word tags. No hashtags, no quotes, no explanation. Example: productivity, design, strategy",
            "messages": [["role": "user", "content": "Generate concept tags for this note:\n\n\(content)"]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: http.statusCode, detail: detail)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ClaudeError.unexpectedBody
        }

        return text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    // MARK: - Errors

    enum ClaudeError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(statusCode: Int, detail: String)
        case unexpectedBody

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Claude API key is not configured."
            case .invalidResponse:
                return "Received an invalid response from Claude."
            case .apiError(let code, let detail):
                return "Claude API error \(code): \(detail)"
            case .unexpectedBody:
                return "Could not parse Claude response."
            }
        }
    }
}
