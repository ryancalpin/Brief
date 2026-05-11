// AIParsingService.swift
// Orchestrates the AI provider chain: OpenRouter → Apple Intelligence → Rule-based

import Foundation
import Observation

// AIProviderChoice kept for backward-compatibility with SettingsViewModel/SettingsView.
// It no longer drives provider selection — the chain auto-detects the best available provider.
enum AIProviderChoice: String, CaseIterable {
    case appleIntelligence = "appleIntelligence"
    case openAI            = "openAI"
    case anthropic         = "anthropic"
    case ruleBased         = "ruleBased"

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .openAI:            return "OpenAI (GPT)"
        case .anthropic:         return "Anthropic (Claude)"
        case .ruleBased:         return "Offline (Basic)"
        }
    }

    var requiresAPIKey: Bool { self == .openAI || self == .anthropic }
}

@Observable
@MainActor
final class AIParsingService {

    var isProcessing = false
    var lastError: Error?

    private let openRouter        = OpenRouterService.shared
    private let appleIntelligence = AppleIntelligenceService()
    private let byokService       = BYOKService()

    // MARK: - Parse

    // Provider chain:
    // 1. OpenRouter (via APIGatewayService) — if configured
    // 2. Apple Intelligence — silent pre-parse on supported devices (iOS 26+)
    // 3. Rule-based — always-on fallback
    func parse(transcript: String) async throws -> AIParseResult {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        // 1. OpenRouter
        if openRouter.isConfigured {
            do {
                return try await openRouter.parse(transcript: transcript)
            } catch {
                lastError = error
            }
        }

        // 2. Apple Intelligence (silent, iOS 26+, no user-facing provider choice)
        if AppleIntelligenceService.isAvailable {
            if let result = try? await appleIntelligence.parse(transcript: transcript) {
                return result
            }
        }

        // 3. Rule-based fallback — never throws
        return byokService.parseRuleBased(transcript: transcript)
    }

    var isConfigured: Bool { openRouter.isConfigured }

    // MARK: - Available providers (for Settings UI — legacy, not used for routing)

    var preferredProvider: AIProviderChoice = .appleIntelligence  // kept for SettingsViewModel compat
    var openAIKey: String  = ""  // kept for SettingsViewModel compat
    var anthropicKey: String = "" // kept for SettingsViewModel compat

    var availableProviders: [AIProviderChoice] {
        var providers: [AIProviderChoice] = []
        if AppleIntelligenceService.isAvailable { providers.append(.appleIntelligence) }
        providers.append(.ruleBased)
        return providers
    }
}

extension AppleIntelligenceError: Equatable {
    static func == (lhs: AppleIntelligenceError, rhs: AppleIntelligenceError) -> Bool {
        switch (lhs, rhs) {
        case (.notAvailable, .notAvailable),
             (.modelUnavailable, .modelUnavailable),
             (.invalidResponse, .invalidResponse): return true
        default: return false
        }
    }
}
