import Foundation

/// Calls the Claude Messages API for Intelligence chat
enum ClaudeService {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct ToolResponse {
        let text: String
        let actions: [SuggestedAction]
    }

    // MARK: - Tool Definitions

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "schedule_echo",
            "description": "Schedule an Echo (reminder/alert) on a handle. The user will see a confirmation card before it executes.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "handle_id":      ["type": "string", "description": "The UUID of the handle to attach the echo to"],
                    "handle_name":    ["type": "string", "description": "The display name of the handle (for the confirmation card)"],
                    "is_recurring":   ["type": "boolean", "description": "Whether the echo repeats on an interval"],
                    "interval_value": ["type": "integer", "description": "Numeric interval value (e.g. 3 for 'every 3 days')"],
                    "interval_unit":  ["type": "string", "enum": ["minutes", "hours", "days", "weeks", "months"], "description": "Interval time unit"],
                    "fire_date":      ["type": "string", "description": "ISO-8601 date-time for the first fire"]
                ],
                "required": ["handle_id", "handle_name", "is_recurring", "interval_value", "interval_unit", "fire_date"]
            ] as [String: Any]
        ],
        [
            "name": "set_note_intent",
            "description": "Set the intent/category of a note. The user will see a confirmation card before it executes.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "note_id":    ["type": "string", "description": "The UUID of the note"],
                    "note_title": ["type": "string", "description": "The title of the note (for the confirmation card)"],
                    "intent":     ["type": "string", "enum": ["idea", "question", "task", "evidence"], "description": "The intent to set"]
                ],
                "required": ["note_id", "note_title", "intent"]
            ] as [String: Any]
        ],
        [
            "name": "promote_to_handle",
            "description": "Promote a section (node) to a handle (loop). The user will see a confirmation card before it executes.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "section_id":      ["type": "string", "description": "The UUID of the section to promote"],
                    "section_preview": ["type": "string", "description": "Short preview of the section content"],
                    "handle_name":     ["type": "string", "description": "Name for the new handle (2-50 chars, letters/numbers/underscores)"]
                ],
                "required": ["section_id", "section_preview", "handle_name"]
            ] as [String: Any]
        ]
    ]

    // MARK: - Send With Tools

    /// Send a conversation with tool definitions so Claude can suggest structured actions.
    static func sendWithTools(
        messages: [Message],
        noteContext: String
    ) async throws -> ToolResponse {
        guard let apiKey = AppConfiguration.claudeAPIKey else {
            throw ClaudeError.missingAPIKey
        }

        let systemPrompt = """
        You are the intelligence assistant inside Obius, a note-taking app. \
        Answer questions about the user's notes and help them stay organised. \
        Be concise and helpful.

        You can suggest actions using your tools. The user will see each action \
        as a card with Accept/Dismiss buttons — the action only executes if \
        accepted. Suggest actions when clearly relevant. You may combine text \
        with tool calls.

        Available intents: idea (blue), question (yellow), task (green), evidence (purple).
        Handle names: 2-50 chars, letters/numbers/underscores only.

        Current workspace context:
        \(noteContext)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "tools": toolDefinitions,
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
              let content = json["content"] as? [[String: Any]] else {
            throw ClaudeError.unexpectedBody
        }

        var textParts: [String] = []
        var actions: [SuggestedAction] = []

        for block in content {
            guard let blockType = block["type"] as? String else { continue }

            if blockType == "text", let text = block["text"] as? String {
                textParts.append(text)
            } else if blockType == "tool_use" {
                if let action = SuggestedAction.from(toolUseBlock: block) {
                    actions.append(action)
                }
            }
        }

        let combinedText = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ToolResponse(text: combinedText, actions: actions)
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

    // MARK: - Temporal Echo Extraction

    struct TemporalEchoSuggestion: Codable {
        let handleId: String       // Handle UUID this echo should attach to, or "new"
        let handleName: String     // Display name for the suggestion card
        let phrase: String         // The temporal phrase detected (e.g. "follow up Thursday")
        let isRecurring: Bool
        let intervalValue: Int     // e.g. 3
        let intervalUnit: String   // "minutes","hours","days","weeks","months"
        let fireDateISO: String    // ISO-8601 fire date
        let noteId: String         // Source note

        // Custom decoding to handle the AI returning numbers as strings
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            handleId = try c.decode(String.self, forKey: .handleId)
            handleName = try c.decode(String.self, forKey: .handleName)
            phrase = try c.decode(String.self, forKey: .phrase)
            fireDateISO = try c.decode(String.self, forKey: .fireDateISO)
            noteId = try c.decode(String.self, forKey: .noteId)
            intervalUnit = try c.decode(String.self, forKey: .intervalUnit)

            // isRecurring: accept bool or string
            if let b = try? c.decode(Bool.self, forKey: .isRecurring) {
                isRecurring = b
            } else if let s = try? c.decode(String.self, forKey: .isRecurring) {
                isRecurring = s.lowercased() == "true"
            } else {
                isRecurring = false
            }

            // intervalValue: accept int or string
            if let i = try? c.decode(Int.self, forKey: .intervalValue) {
                intervalValue = i
            } else if let s = try? c.decode(String.self, forKey: .intervalValue),
                      let i = Int(s) {
                intervalValue = i
            } else {
                intervalValue = 0
            }
        }

        private enum CodingKeys: String, CodingKey {
            case handleId, handleName, phrase, isRecurring
            case intervalValue, intervalUnit, fireDateISO, noteId
        }

        // Keep the memberwise init for encoding
        init(handleId: String, handleName: String, phrase: String, isRecurring: Bool,
             intervalValue: Int, intervalUnit: String, fireDateISO: String, noteId: String) {
            self.handleId = handleId
            self.handleName = handleName
            self.phrase = phrase
            self.isRecurring = isRecurring
            self.intervalValue = intervalValue
            self.intervalUnit = intervalUnit
            self.fireDateISO = fireDateISO
            self.noteId = noteId
        }
    }

    /// Analyze notes for temporal phrases and suggest Echo configurations.
    static func extractTemporalEchoes(_ noteSummaries: String, handles: String) async throws -> [TemporalEchoSuggestion] {
        guard let apiKey = AppConfiguration.claudeAPIKey else {
            throw ClaudeError.missingAPIKey
        }

        let systemPrompt = """
        You are a temporal phrase detector for Obius, a note-taking app with Echoes (reminders). \
        Analyze the notes and identify temporal phrases that imply the user should be reminded \
        about something. Examples: "follow up Thursday", "revisit in 2 weeks", "check back next month", \
        "dentist appointment at 3pm", "deadline Friday", "every Monday".

        You also receive a list of existing handles (loops). If a temporal phrase relates to a specific \
        existing handle, use that handle's ID and displayName. Otherwise, set handleId to "new" and \
        set handleName to a short, descriptive snake_case name derived from the context \
        (e.g. "dentist_appointment", "client_followup", "weekly_standup"). \
        NEVER use "none" as a handleName — always derive a meaningful name from the content.

        Return a JSON array of objects with: \
        "handleId" (UUID of an existing handle, or "new" if suggesting a new handle), \
        "handleName" (display name — MUST be descriptive, e.g. "dentist_appointment" not "none"), \
        "phrase" (the exact temporal phrase found in the note), \
        "isRecurring" (boolean), \
        "intervalValue" (integer, e.g. 1 for "every week"), \
        "intervalUnit" (one of: minutes, hours, days, weeks, months), \
        "fireDateISO" (ISO-8601 date-time for when the echo should first fire), \
        "noteId" (the note's ID where the phrase was found).

        For non-recurring echoes, set intervalValue=0 and intervalUnit="days". \
        For recurring, set the appropriate interval. \
        Use today's date context to compute fireDateISO from relative phrases like "Thursday" or "next week". \
        Today is \(ISO8601DateFormatter().string(from: Date())). \
        Max 3 suggestions. Return [] if nothing qualifies. \
        Return ONLY the JSON array, no other text.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 512,
            "system": systemPrompt,
            "messages": [["role": "user", "content": "Notes:\n\(noteSummaries)\n\nHandles:\n\(handles)"]]
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

        guard let startIdx = text.firstIndex(of: "["),
              let endIdx = text.lastIndex(of: "]") else {
            return []
        }
        let jsonString = String(text[startIdx...endIdx])
        guard let jsonData = jsonString.data(using: .utf8) else { return [] }

        let suggestions = try JSONDecoder().decode([TemporalEchoSuggestion].self, from: jsonData)
        return Array(suggestions.prefix(3))
    }

    // MARK: - Entity Extraction

    /// Analyze note sections and suggest entities that could become Loops.
    static func extractEntities(from sections: [(id: String, content: String)]) async throws -> [ExtractedEntity] {
        guard let apiKey = AppConfiguration.claudeAPIKey else {
            throw ClaudeError.missingAPIKey
        }

        let sectionsText = sections.map { "sectionId: \($0.id)\n\($0.content)" }.joined(separator: "\n---\n")

        let systemPrompt = """
        Analyze the following note sections and identify recurring entities (people, places, projects, \
        topics, lists) that the user references repeatedly or that would benefit from being a synced \
        Loop (a content block that stays consistent across pages).

        Return a JSON array of objects with: "name" (display name), "handleName" (lowercase, \
        underscores, 2-50 chars), "reason" (1 sentence why), "sectionId" (which section contains it).

        Only suggest entities that genuinely recur or would benefit from syncing. Max 3 suggestions. \
        Return [] if nothing qualifies. Return ONLY the JSON array, no other text.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [["role": "user", "content": sectionsText]]
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

        // Parse JSON array from response
        guard let startIdx = text.firstIndex(of: "["),
              let endIdx = text.lastIndex(of: "]") else {
            return []
        }
        let jsonString = String(text[startIdx...endIdx])
        guard let jsonData = jsonString.data(using: .utf8) else { return [] }

        let entities = try JSONDecoder().decode([ExtractedEntity].self, from: jsonData)
        return Array(entities.prefix(3))
    }

    // MARK: - Note Analysis (Insight Engine)

    /// Analyze note summaries and return AI-powered suggestions as a JSON array string.
    static func analyzeNotes(_ noteSummaries: String) async throws -> String {
        guard let apiKey = AppConfiguration.claudeAPIKey else {
            throw ClaudeError.missingAPIKey
        }

        let systemPrompt = """
        You are an insight engine for Obius, a note-taking app. Analyze the provided notes \
        and return a JSON array of suggestions. Each suggestion object must have: \
        "type" (one of: intent_correction, connection, handle_promotion), \
        "noteId" (the primary note's ID), "title" (short insight title), "body" (1-2 sentence explanation). \
        When a suggestion involves additional notes, include "relatedNoteIds" as an array of their IDs \
        (e.g. for connection: both related note IDs; for handle_promotion: all notes containing that concept).

        Suggestion types:
        - intent_correction: Note tagged as one intent but content suggests another (idea/question/task/evidence).
        - connection: Two or more notes share overlapping themes or could reference each other.
        - handle_promotion: A section/concept mentioned across notes that deserves its own handle (loop).

        Do NOT suggest echo/reminder types — those are handled by a separate system. \
        Return at most 5 suggestions. If nothing stands out, return []. \
        Return ONLY the JSON array, no other text.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 512,
            "system": systemPrompt,
            "messages": [["role": "user", "content": noteSummaries]]
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
