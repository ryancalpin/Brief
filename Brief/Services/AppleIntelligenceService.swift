// AppleIntelligenceService.swift
// On-device AI parsing using Foundation Models (iOS 26+ / Apple Intelligence)

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps Foundation Models for on-device AI parsing.
/// Only functional on iOS 26+ devices with Apple Intelligence enabled.
final class AppleIntelligenceService: Sendable {

    enum AvailabilityStatus {
        case available
        case requiresiOS26
        case appleIntelligenceDisabled
        case modelUnavailable
    }

    static var availabilityStatus: AvailabilityStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled, .appleIntelligenceNotSupported:
                    return .appleIntelligenceDisabled
                default:
                    return .modelUnavailable
                }
            }
        }
        #endif
        return .requiresiOS26
    }

    static var isAvailable: Bool {
        availabilityStatus == .available
    }

    // MARK: - Parse

    func parse(transcript: String) async throws -> AIParseResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await parseWithFoundationModels(transcript: transcript)
        }
        #endif
        throw AppleIntelligenceError.notAvailable
    }

    // MARK: - Private

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func parseWithFoundationModels(transcript: String) async throws -> AIParseResult {
        guard SystemLanguageModel.default.availability == .available else {
            throw AppleIntelligenceError.modelUnavailable
        }

        let session = LanguageModelSession()
        let prompt = """
        \(AIParseResult.systemPrompt())

        Voice input: \(transcript)
        """

        let response = try await session.respond(to: prompt)
        let text = response.content

        // Extract JSON from the response
        guard let jsonRange = extractJSONRange(from: text),
              let data = String(text[jsonRange]).data(using: .utf8) else {
            throw AppleIntelligenceError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AIParseResult.self, from: data)
    }
    #endif

    private func extractJSONRange(from text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        guard start <= end else { return nil }
        return start...end
    }
}

enum AppleIntelligenceError: LocalizedError {
    case notAvailable
    case modelUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence requires iOS 26 or later."
        case .modelUnavailable:
            return "The language model is currently unavailable. Please enable Apple Intelligence in Settings."
        case .invalidResponse:
            return "The AI returned an unexpected response format."
        }
    }
}
