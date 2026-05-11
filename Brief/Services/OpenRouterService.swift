// OpenRouterService.swift
// All AI API calls go through this service via APIGatewayService

import Foundation

final class OpenRouterService: Sendable {

    static let shared = OpenRouterService()
    static let defaultFastModel = "google/gemini-flash-2.5"
    static let defaultDeepModel = "anthropic/claude-sonnet-4-6"

    private let gateway = APIGatewayService.shared
    private init() {}

    // MARK: - Availability

    var isConfigured: Bool {
        (try? gateway.requestConfig()) != nil
    }

    // MARK: - Parse

    // One-shot parse: transcript → AIParseResult
    // Returns JSON only. Strips markdown fences before parsing.
    func parse(
        transcript: String,
        model: String = defaultFastModel
    ) async throws -> AIParseResult {
        let config = try gateway.requestConfig()
        let url = URL(string: "\(config.baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        config.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": AIParseResult.systemPrompt()],
                ["role": "user",   "content": transcript]
            ],
            "temperature": 0.1,
            "max_tokens": 600
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard var content = completion.choices.first?.message.content else {
            throw OpenRouterError.emptyResponse
        }
        content = stripFences(content)
        guard let jsonData = content.data(using: .utf8) else {
            throw OpenRouterError.invalidJSON
        }
        return try JSONDecoder().decode(AIParseResult.self, from: jsonData)
    }

    // MARK: - Converse

    // Multi-turn conversation
    func converse(
        history: [ConvoMessage],
        newMessage: String,
        model: String = defaultFastModel
    ) async throws -> String {
        let config = try gateway.requestConfig()
        let url = URL(string: "\(config.baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        config.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        var messages: [[String: String]] = [
            ["role": "system", "content": Self.conversationSystemPrompt]
        ]
        messages += history.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": newMessage])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 300
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return completion.choices.first?.message.content ?? ""
    }

    // MARK: - Helpers

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.network("Invalid response type")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenRouterError.api(http.statusCode, body)
        }
    }

    private func stripFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```json") { result = String(result.dropFirst(7)) }
        else if result.hasPrefix("```") { result = String(result.dropFirst(3)) }
        if result.hasSuffix("```") { result = String(result.dropLast(3)) }
        if let start = result.firstIndex(of: "{"), let end = result.lastIndex(of: "}") {
            return String(result[start...end])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let conversationSystemPrompt = """
    You are Brief, a private ambient AI assistant on iPhone and Apple Watch.
    Help the user capture thoughts, manage tasks, and think through ideas.
    Be concise — responses should be 1-3 sentences unless the user asks
    for more detail. Respond conversationally. You have no persistent
    memory in this version.
    """
}

// MARK: - Supporting types

struct ConvoMessage: Codable, Sendable {
    var role: String    // "user" or "assistant"
    var content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

enum OpenRouterError: LocalizedError {
    case network(String)
    case api(Int, String)
    case emptyResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .network(let msg):        return "Network error: \(msg)"
        case .api(let code, let body): return "API error \(code): \(body.prefix(200))"
        case .emptyResponse:           return "The AI returned an empty response."
        case .invalidJSON:             return "The AI returned an unexpected format."
        }
    }
}
