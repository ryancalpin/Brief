// OpenRouterService.swift
// All AI API calls go through this service via APIGatewayService.
// Model strings are pulled from SettingsViewModel so users can configure them.

import Foundation

final class OpenRouterService: Sendable {

    static let shared = OpenRouterService()

    // User-configurable defaults — SettingsViewModel persists these.
    // These are just the factory defaults; actual values come from Settings.
    static let defaultFastModel = "google/gemini-flash-2.5"
    static let defaultDeepModel = "anthropic/claude-sonnet-4-6"

    private let gateway = APIGatewayService.shared
    private init() {}

    // MARK: - Availability

    var isConfigured: Bool {
        (try? gateway.requestConfig()) != nil
    }

    // MARK: - Active models (from settings, with fallback to defaults)

    var fastModel: String {
        let settings = SettingsViewModel.shared
        return settings.fastModel.isEmpty ? Self.defaultFastModel : settings.fastModel
    }

    var deepModel: String {
        let settings = SettingsViewModel.shared
        return settings.deepModel.isEmpty ? Self.defaultDeepModel : settings.deepModel
    }

    // MARK: - Parse

    // One-shot parse: transcript → AIParseResult
    // Returns JSON only. Strips markdown fences before parsing.
    func parse(
        transcript: String,
        model: String? = nil
    ) async throws -> AIParseResult {
        let config = try gateway.requestConfig()
        let url = URL(string: "\(config.baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        config.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let selectedModel = model ?? fastModel
        let body: [String: Any] = [
            "model": selectedModel,
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

    // MARK: - Converse (multi-turn)

    func converse(
        history: [ConvoMessage],
        newMessage: String,
        model: String? = nil
    ) async throws -> String {
        let config = try gateway.requestConfig()
        let url = URL(string: "\(config.baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        config.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt(history: history)]
        ]
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": newMessage])

        let selectedModel = model ?? fastModel
        let body: [String: Any] = [
            "model": selectedModel,
            "messages": messages,
            "temperature": 0.5,
            "max_tokens": 500
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw OpenRouterError.emptyResponse
        }
        return content
    }

    // MARK: - Helpers

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.noResponse
        }
        guard 200...299 ~= httpResponse.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenRouterError.httpError(httpResponse.statusCode, body)
        }
    }

    private func stripFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = String(t.dropFirst(3))
            if t.hasPrefix("json") { t = String(t.dropFirst(4)) }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if t.hasSuffix("```") {
            t = String(t.dropLast(3))
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    private func systemPrompt(history: [ConvoMessage]) -> String {
        """
        You are Brief, a voice-first personal assistant. Keep responses conversational and brief (1-2 sentences max). You have access to the conversation history for context. Be helpful, warm, and concise.
        """
    }
}

// MARK: - Types

struct ConvoMessage: Codable {
    let role: String  // "user" or "assistant"
    let content: String
}

struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

enum OpenRouterError: LocalizedError {
    case notConfigured
    case noResponse
    case httpError(Int, String)
    case emptyResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenRouter is not configured. Add an API key in Settings."
        case .noResponse:
            return "No response from AI service. Check your network connection."
        case .httpError(let code, let body):
            return "AI service returned \\(code): \\(body.prefix(200))"
        case .emptyResponse:
            return "AI returned an empty response."
        case .invalidJSON:
            return "AI response was not valid JSON."
        }
    }
}
