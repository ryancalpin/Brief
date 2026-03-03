// BYOKService.swift
// Bring-Your-Own-Key: OpenAI and Anthropic API integration for AI parsing

import Foundation

final class BYOKService: Sendable {

    // MARK: - OpenAI

    func parseWithOpenAI(transcript: String, apiKey: String, model: String = "gpt-4o-mini") async throws -> AIParseResult {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": AIParseResult.systemPrompt()],
                ["role": "user", "content": transcript]
            ],
            "temperature": 0.1,
            "max_tokens": 500,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BYOKError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw BYOKError.invalidAPIKey("OpenAI")
            }
            throw BYOKError.apiError("OpenAI returned \(httpResponse.statusCode): \(errorBody)")
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw BYOKError.invalidResponse
        }

        return try JSONDecoder().decode(AIParseResult.self, from: jsonData)
    }

    // MARK: - Anthropic

    func parseWithAnthropic(transcript: String, apiKey: String, model: String = "claude-haiku-4-5-20251001") async throws -> AIParseResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "system": AIParseResult.systemPrompt(),
            "messages": [
                ["role": "user", "content": transcript]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BYOKError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw BYOKError.invalidAPIKey("Anthropic")
            }
            throw BYOKError.apiError("Anthropic returned \(httpResponse.statusCode): \(errorBody)")
        }

        let anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = anthropicResponse.content.first?.text else {
            throw BYOKError.invalidResponse
        }

        // Extract JSON from response (Claude may wrap it in markdown)
        let jsonString = extractJSON(from: text)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw BYOKError.invalidResponse
        }

        return try JSONDecoder().decode(AIParseResult.self, from: jsonData)
    }

    // MARK: - Rule-Based Fallback

    func parseRuleBased(transcript: String) -> AIParseResult {
        return RuleBasedParser.parse(transcript: transcript)
    }

    // MARK: - Helpers

    private func extractJSON(from text: String) -> String {
        // Strip markdown code blocks if present
        if let start = text.range(of: "```json\n") {
            let contentStart = start.upperBound
            if let end = text.range(of: "\n```", range: contentStart..<text.endIndex) {
                return String(text[contentStart..<end.lowerBound])
            }
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}

// MARK: - Response models

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct AnthropicResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}

// MARK: - Rule-Based Parser

struct RuleBasedParser {
    static func parse(transcript: String) -> AIParseResult {
        let lower = transcript.lowercased()

        // Determine item type and destination
        let (itemType, destination) = classify(lower)

        // Simple title extraction: capitalize first sentence
        let title = extractTitle(from: transcript)

        // Try to extract a date from the text
        let dueDate = extractDate(from: lower)

        // Extract simple priority signals
        let priority = extractPriority(from: lower)

        return AIParseResult(
            itemType: itemType,
            destination: destination,
            title: title,
            content: transcript != title ? transcript : nil,
            dueDateISO: dueDate,
            priority: priority,
            tags: [],
            startDateISO: nil,
            endDateISO: nil,
            location: nil
        )
    }

    private static func classify(_ text: String) -> (String, String) {
        let reminderTriggers = ["remind me", "don't forget", "remember to", "i need to", "i have to", "todo"]
        let noteTriggers = ["note that", "remember that", "write down", "jot down", "keep in mind"]
        let calendarTriggers = ["schedule", "meeting", "appointment", "event", "add to calendar"]
        let listTriggers = ["shopping list", "grocery list", "to-do list", "todo list", "list of"]

        if listTriggers.contains(where: { text.contains($0) }) {
            return ("list", "reminders")
        }
        if reminderTriggers.contains(where: { text.contains($0) }) {
            return ("reminder", "reminders")
        }
        if noteTriggers.contains(where: { text.contains($0) }) {
            return ("note", "notes")
        }
        if calendarTriggers.contains(where: { text.contains($0) }) {
            return ("calendarEvent", "calendar")
        }
        return ("generic", "briefOnly")
    }

    private static func extractTitle(from text: String) -> String {
        // Remove filler phrases and capitalize
        var title = text
        let fillers = ["remind me to ", "note that ", "remember that ", "write down ", "jot down "]
        for filler in fillers {
            if title.lowercased().hasPrefix(filler) {
                title = String(title.dropFirst(filler.count))
                break
            }
        }
        let first = title.prefix(1).uppercased()
        let rest = title.dropFirst()
        title = first + rest
        // Truncate at 80 chars
        if title.count > 80 {
            title = String(title.prefix(80)) + "…"
        }
        return title
    }

    private static func extractDate(from text: String) -> String? {
        let calendar = Calendar.current
        let now = Date()

        if text.contains("tomorrow") {
            let date = calendar.date(byAdding: .day, value: 1, to: now)
            return date.map { ISO8601DateFormatter().string(from: $0) }
        }
        if text.contains("next week") {
            let date = calendar.date(byAdding: .weekOfYear, value: 1, to: now)
            return date.map { ISO8601DateFormatter().string(from: $0) }
        }
        if text.contains("tonight") || text.contains("this evening") {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = 19
            comps.minute = 0
            let date = calendar.date(from: comps)
            return date.map { ISO8601DateFormatter().string(from: $0) }
        }
        return nil
    }

    private static func extractPriority(from text: String) -> String? {
        if text.contains("urgent") || text.contains("asap") || text.contains("immediately") {
            return "urgent"
        }
        if text.contains("important") || text.contains("high priority") {
            return "high"
        }
        if text.contains("whenever") || text.contains("low priority") || text.contains("eventually") {
            return "low"
        }
        return nil
    }
}

// MARK: - Errors

enum BYOKError: LocalizedError {
    case networkError(String)
    case invalidAPIKey(String)
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .networkError(let msg):   return "Network error: \(msg)"
        case .invalidAPIKey(let p):    return "Invalid \(p) API key. Check your key in Settings."
        case .apiError(let msg):       return msg
        case .invalidResponse:         return "The AI service returned an unexpected response."
        }
    }
}
