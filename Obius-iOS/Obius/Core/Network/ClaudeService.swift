import Foundation

/// Proxies all AI calls through the Supabase ai-proxy Edge Function.
/// The API key lives server-side — no client-side secrets needed.
/// Uses direct URLSession calls to avoid the Supabase Swift SDK sending stale JWTs.
enum ClaudeService {

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct ToolResponse {
        let text: String
        let actions: [SuggestedAction]
    }

    // MARK: - Request / Response Types

    private struct AIProxyRequest: Encodable {
        let action: String
        // Flexible payload fields — only set the ones each action needs.
        var messages: [Message]?
        var noteContext: String?
        var content: String?
        var noteSummaries: String?
        var handles: String?
        var sectionsText: String?
    }

    /// Response for actions that return a single text string.
    private struct TextResponse: Decodable {
        let text: String
    }

    // MARK: - Direct HTTP Helper

    /// Call the ai-proxy edge function directly via URLSession.
    /// Sends the anon key + current session JWT (if available), avoiding the
    /// Supabase Swift SDK which can send stale/expired tokens.
    private static func invokeProxy<T: Decodable>(_ request: AIProxyRequest) async throws -> T {
        let data = try await invokeProxyRaw(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func invokeProxyRaw(_ request: AIProxyRequest) async throws -> Data {
        let url = URL(string: "\(AppConfiguration.supabaseURL)/functions/v1/ai-proxy")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(AppConfiguration.supabaseAnonKey, forHTTPHeaderField: "apikey")

        urlRequest.setValue("Bearer \(AppConfiguration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.proxyError("HTTP \(httpResponse.statusCode): \(body)")
        }

        return data
    }

    // MARK: - Tier Gate

    private static func checkAIGate() async throws {
        let allowed = await MainActor.run { TierManager.shared.requireAI() }
        guard allowed else {
            throw ClaudeError.proxyError("AI Credit limit reached. Upgrade — or add the Power Pack — for more.")
        }
    }

    private static func recordAIUsage(data: Data? = nil) async {
        var tokens = 0
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let usage = json["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            tokens = input + output
        }
        // Local estimate if we couldn't parse; server tracks exact count
        if tokens == 0 { tokens = 500 }
        await MainActor.run { TierManager.shared.recordTokenUsage(tokens) }
        // Reconcile authoritative monthly usage from the server in the background
        Task { await MainActor.run { Task { await TierManager.shared.syncCreditUsage() } } }
    }

    // MARK: - Send With Tools

    /// Send a conversation with tool definitions so Claude can suggest structured actions.
    static func sendWithTools(
        messages: [Message],
        noteContext: String
    ) async throws -> ToolResponse {
        try await checkAIGate()
        let request = AIProxyRequest(
            action: "send_with_tools",
            messages: messages,
            noteContext: noteContext
        )

        let data = try await invokeProxyRaw(request)
        await recordAIUsage(data: data)

        let rawString = String(data: data, encoding: .utf8) ?? ""

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.proxyError("Could not parse response: \(rawString.prefix(200))")
        }

        // The Anthropic API returns content as an array of blocks
        guard let content = json["content"] as? [[String: Any]] else {
            // Check if there's an error message in the response
            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw ClaudeError.proxyError(message)
            }
            let keys = Array(json.keys).joined(separator: ", ")
            let stopReason = json["stop_reason"] as? String ?? "unknown"
            throw ClaudeError.proxyError("Unexpected response (keys: \(keys), stop_reason: \(stopReason)). Raw: \(rawString.prefix(300))")
        }

        var textParts: [String] = []
        var actions: [SuggestedAction] = []
        var failedTools: [(name: String, reason: String)] = []

        for block in content {
            guard let blockType = block["type"] as? String else { continue }

            if blockType == "text", let text = block["text"] as? String {
                textParts.append(text)
            } else if blockType == "tool_use" {
                if let action = SuggestedAction.from(toolUseBlock: block) {
                    actions.append(action)
                } else {
                    let toolName = block["name"] as? String ?? "unknown"
                    let inputKeys = (block["input"] as? [String: Any])?.keys.joined(separator: ", ") ?? "no input"
                    let hasId = block["id"] != nil
                    failedTools.append((name: toolName, reason: "id=\(hasId), inputKeys=[\(inputKeys)]"))
                    print("[ClaudeService] Failed to parse tool_use: \(toolName), id=\(hasId), inputKeys=[\(inputKeys)], raw=\(block)")
                }
            }
        }

        // If all tool calls failed to parse, show exactly what went wrong
        if actions.isEmpty && !failedTools.isEmpty {
            let details = failedTools.map { "\($0.name) (\($0.reason))" }.joined(separator: "; ")
            textParts.append("Tool calls failed to parse: \(details). Please try again.")
        }

        let combinedText = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ToolResponse(text: combinedText, actions: actions)
    }

    // MARK: - Streaming (Send With Tools)

    /// Incremental event emitted while `sendWithToolsStream` is running.
    enum StreamEvent {
        /// Accumulated free-text Claude has emitted so far (across all text blocks).
        case partialText(String)
        /// A tool_use block opened with the given tool name. `partialJSON` is the
        /// accumulated input JSON so far for that block (may be empty initially).
        case partialTool(name: String, partialJSON: String)
        /// A tool_use block finished and parsed successfully into an action.
        case toolComplete(SuggestedAction)
        /// Stream finished. `text` is final accumulated text, `actions` is the
        /// ordered list of fully-parsed actions (same as toolComplete emissions).
        case done(text: String, actions: [SuggestedAction])
    }

    /// Stream a tool-augmented response. Yields incremental events as Anthropic's
    /// SSE deltas arrive so the UI can show the page being built in real time.
    static func sendWithToolsStream(
        messages: [Message],
        noteContext: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await checkAIGate()

                    let url = URL(string: "\(AppConfiguration.supabaseURL)/functions/v1/ai-proxy")!
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue(AppConfiguration.supabaseAnonKey, forHTTPHeaderField: "apikey")
                    urlRequest.setValue("Bearer \(AppConfiguration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.timeoutInterval = 120

                    let body = AIProxyRequest(
                        action: "send_with_tools_stream",
                        messages: messages,
                        noteContext: noteContext
                    )
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw ClaudeError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        var collected = Data()
                        for try await byte in bytes {
                            collected.append(byte)
                            if collected.count > 4096 { break }
                        }
                        let detail = String(data: collected, encoding: .utf8) ?? ""
                        // The deployed ai-proxy may predate the streaming action.
                        // Fall back to the non-streaming endpoint and synthesize
                        // a single batch of events so callers don't have to know.
                        if http.statusCode == 400 && detail.contains("UNKNOWN_ACTION") {
                            let fallback = try await sendWithTools(
                                messages: messages,
                                noteContext: noteContext
                            )
                            if !fallback.text.isEmpty {
                                continuation.yield(.partialText(fallback.text))
                            }
                            for action in fallback.actions {
                                continuation.yield(.toolComplete(action))
                            }
                            continuation.yield(.done(text: fallback.text, actions: fallback.actions))
                            continuation.finish()
                            return
                        }
                        throw ClaudeError.proxyError("HTTP \(http.statusCode): \(detail)")
                    }

                    var textParts: [String] = []
                    var combinedText: String = ""
                    var completedActions: [SuggestedAction] = []

                    struct OpenBlock {
                        var type: String       // "text" | "tool_use"
                        var toolId: String?
                        var toolName: String?
                        var partialJSON: String = ""
                    }
                    var openBlocks: [Int: OpenBlock] = [:]
                    var totalInputTokens = 0
                    var totalOutputTokens = 0

                    for try await line in bytes.lines {
                        // Anthropic SSE frames look like:
                        //   event: content_block_delta
                        //   data: {"type":"content_block_delta","index":0,...}
                        //
                        // URLSession's `.lines` strips trailing newlines but
                        // delivers each line individually, so we only need to
                        // parse the data: lines.
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, payload != "[DONE]" else { continue }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = obj["type"] as? String else {
                            continue
                        }

                        switch type {
                        case "message_start":
                            if let msg = obj["message"] as? [String: Any],
                               let usage = msg["usage"] as? [String: Any] {
                                totalInputTokens = usage["input_tokens"] as? Int ?? 0
                                totalOutputTokens = usage["output_tokens"] as? Int ?? 0
                            }
                        case "content_block_start":
                            guard let index = obj["index"] as? Int,
                                  let block = obj["content_block"] as? [String: Any],
                                  let blockType = block["type"] as? String else { continue }
                            var open = OpenBlock(type: blockType)
                            if blockType == "tool_use" {
                                open.toolId = block["id"] as? String
                                open.toolName = block["name"] as? String
                                if let name = open.toolName {
                                    continuation.yield(.partialTool(name: name, partialJSON: ""))
                                }
                            } else if blockType == "text",
                                      let seed = block["text"] as? String,
                                      !seed.isEmpty {
                                combinedText += seed
                                continuation.yield(.partialText(combinedText))
                            }
                            openBlocks[index] = open
                        case "content_block_delta":
                            guard let index = obj["index"] as? Int,
                                  var open = openBlocks[index],
                                  let delta = obj["delta"] as? [String: Any],
                                  let deltaType = delta["type"] as? String else { continue }
                            if deltaType == "text_delta", let text = delta["text"] as? String {
                                combinedText += text
                                continuation.yield(.partialText(combinedText))
                            } else if deltaType == "input_json_delta",
                                      let partial = delta["partial_json"] as? String {
                                open.partialJSON += partial
                                openBlocks[index] = open
                                if let name = open.toolName {
                                    continuation.yield(.partialTool(name: name, partialJSON: open.partialJSON))
                                }
                            }
                        case "content_block_stop":
                            guard let index = obj["index"] as? Int,
                                  let open = openBlocks.removeValue(forKey: index) else { continue }
                            if open.type == "text" {
                                // Push the (now-final) text fragment into the parts list. We've
                                // already streamed it via .partialText, so nothing more to emit.
                                let fragment = String(combinedText.suffix(combinedText.count - textParts.joined().count))
                                textParts.append(fragment)
                            } else if open.type == "tool_use",
                                      let id = open.toolId,
                                      let name = open.toolName {
                                let inputDict: [String: Any]
                                if open.partialJSON.isEmpty {
                                    inputDict = [:]
                                } else if let data = open.partialJSON.data(using: .utf8),
                                          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    inputDict = parsed
                                } else {
                                    print("[ClaudeService] tool_use \(name) had unparseable JSON: \(open.partialJSON.prefix(200))")
                                    continue
                                }
                                let toolUseBlock: [String: Any] = [
                                    "id": id,
                                    "name": name,
                                    "input": inputDict
                                ]
                                if let action = SuggestedAction.from(toolUseBlock: toolUseBlock) {
                                    completedActions.append(action)
                                    continuation.yield(.toolComplete(action))
                                } else {
                                    print("[ClaudeService] failed to parse completed tool: \(name)")
                                }
                            }
                        case "message_delta":
                            if let usage = obj["usage"] as? [String: Any],
                               let out = usage["output_tokens"] as? Int {
                                totalOutputTokens = out
                            }
                        case "message_stop":
                            break
                        default:
                            break
                        }
                    }

                    let finalText = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.yield(.done(text: finalText, actions: completedActions))

                    let tokens = max(totalInputTokens + totalOutputTokens, 500)
                    await MainActor.run { TierManager.shared.recordTokenUsage(tokens) }
                    Task { await MainActor.run { Task { await TierManager.shared.syncCreditUsage() } } }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Extract progressive text from a tool_use's partial JSON without requiring
    /// the JSON to be complete. Returns the current value of `new_body` /
    /// `new_content` / similar text-bearing fields — even if the closing quote
    /// hasn't streamed yet. Returns nil if no recognizable field has begun.
    static func extractStreamingText(partialJSON: String, toolName: String) -> String? {
        let keys: [String]
        switch toolName {
        case "rewrite_page":             keys = ["new_body", "new_content"]
        case "update_page_body":         keys = ["new_body"]
        case "update_section_content":   keys = ["new_content"]
        case "update_loop_content":      keys = ["new_content"]
        case "update_interstitial_content": keys = ["new_content"]
        case "create_section", "add_section", "create_node": keys = ["content"]
        default: return nil
        }

        for key in keys {
            // Find `"key":"` and grab everything after until the next unescaped quote
            // (or EOF if the value is still streaming).
            let needle = "\"\(key)\":"
            guard let range = partialJSON.range(of: needle) else { continue }
            var i = range.upperBound
            // Skip whitespace
            while i < partialJSON.endIndex, partialJSON[i].isWhitespace { i = partialJSON.index(after: i) }
            guard i < partialJSON.endIndex, partialJSON[i] == "\"" else { continue }
            i = partialJSON.index(after: i)
            var out = ""
            while i < partialJSON.endIndex {
                let c = partialJSON[i]
                if c == "\\" {
                    let next = partialJSON.index(after: i)
                    guard next < partialJSON.endIndex else { break }
                    let esc = partialJSON[next]
                    switch esc {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    default: out.append(esc)
                    }
                    i = partialJSON.index(after: next)
                    continue
                }
                if c == "\"" { break }
                out.append(c)
                i = partialJSON.index(after: i)
            }
            return out
        }
        return nil
    }

    // MARK: - Send Chat (no tools)

    /// Send a conversation without tools — returns a plain text response.
    static func sendChat(
        messages: [Message],
        noteContext: String
    ) async throws -> String {
        try await checkAIGate()
        await recordAIUsage()
        let request = AIProxyRequest(
            action: "send_chat",
            messages: messages,
            noteContext: noteContext
        )
        let response: TextResponse = try await invokeProxy(request)
        return response.text
    }

    // MARK: - Title Generation

    /// Generate a short AI title (2-5 words) from note content.
    static func generateTitle(from content: String) async throws -> String {
        try await checkAIGate()
        await recordAIUsage()
        let request = AIProxyRequest(action: "generate_title", content: content)
        let response: TextResponse = try await invokeProxy(request)
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tag Generation

    /// Generate concept tags from note content. Returns 1-5 single-word tags.
    static func generateTags(from content: String) async throws -> [String] {
        try await checkAIGate()
        await recordAIUsage()
        let request = AIProxyRequest(action: "generate_tags", content: content)
        let response: TextResponse = try await invokeProxy(request)
        return response.text
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
        try await checkAIGate()
        await recordAIUsage()
        let request = AIProxyRequest(
            action: "extract_temporal_echoes",
            noteSummaries: noteSummaries,
            handles: handles
        )
        let response: TextResponse = try await invokeProxy(request)

        let text = response.text
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
        try await checkAIGate()
        await recordAIUsage()
        let sectionsText = sections.map { "sectionId: \($0.id)\n\($0.content)" }.joined(separator: "\n---\n")
        let request = AIProxyRequest(action: "extract_entities", sectionsText: sectionsText)
        let response: TextResponse = try await invokeProxy(request)

        let text = response.text
        guard let startIdx = text.firstIndex(of: "["),
              let endIdx = text.lastIndex(of: "]") else {
            return []
        }
        let jsonString = String(text[startIdx...endIdx])
        guard let jsonData = jsonString.data(using: .utf8) else { return [] }

        let entities = try JSONDecoder().decode([ExtractedEntity].self, from: jsonData)
        return Array(entities.prefix(3))
    }

    // MARK: - Errors

    enum ClaudeError: LocalizedError {
        case invalidResponse
        case unexpectedBody
        case proxyError(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Received an invalid response from the AI service."
            case .unexpectedBody:
                return "Could not parse AI response."
            case .proxyError(let detail):
                return "AI proxy error: \(detail)"
            }
        }
    }
}
