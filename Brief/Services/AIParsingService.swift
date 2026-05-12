// AIParsingService.swift
// Orchestrates the AI provider chain: OpenRouter → Apple Intelligence → Rule-based

import Foundation
import Observation

@Observable
@MainActor
final class AIParsingService {

    var isProcessing = false
    var lastError: Error?
    private(set) var lastProvider: String = "ruleBased"  // updated after each parse()

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
                let result = try await openRouter.parse(transcript: transcript)
                lastProvider = "openrouter"
                return result
            } catch {
                lastError = error
            }
        }

        // 2. Apple Intelligence (silent, iOS 26+, no user-facing provider choice)
        if AppleIntelligenceService.isAvailable {
            if let result = try? await appleIntelligence.parse(transcript: transcript) {
                lastProvider = "appleIntelligence"
                return result
            }
        }

        // 3. Rule-based fallback — never throws
        lastProvider = "ruleBased"
        return byokService.parseRuleBased(transcript: transcript)
    }

    var isConfigured: Bool { openRouter.isConfigured }
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
