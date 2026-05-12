// AIParsingService.swift
// Orchestrates the AI provider chain: OpenRouter → Apple Intelligence → Rule-based.
// Exposes per-provider errors so the UI can show fallback indicators.

import Foundation
import Observation

/// Provider-level outcome — surfaced to the UI so users know when a configured
/// provider fell through and the app used a lower-tier fallback.
enum AIProviderOutcome: Equatable {
    case success
    case failed(Error)

    static func == (lhs: AIProviderOutcome, rhs: AIProviderOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): return true
        case (.failed(let a), .failed(let b)):
            return a.localizedDescription == b.localizedDescription
        default: return false
        }
    }
}

@Observable
@MainActor
final class AIParsingService: @unchecked Sendable {

    var isProcessing = false
    var lastError: Error?
    private(set) var lastProvider: String = "ruleBased"  // updated after each parse()

    // Exposed: was the preferred provider (OpenRouter) configured but failed?
    var openRouterFailed: Bool = false
    var openRouterLastError: Error?

    // Exposed: did Apple Intelligence attempt but fail?
    var appleIntelligenceFailed: Bool = false

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
        openRouterFailed = false
        openRouterLastError = nil
        appleIntelligenceFailed = false
        defer { isProcessing = false }

        // 1. OpenRouter
        if openRouter.isConfigured {
            do {
                let result = try await openRouter.parse(transcript: transcript)
                lastProvider = "openrouter"
                return result
            } catch {
                lastError = error
                openRouterFailed = true
                openRouterLastError = error
                // Fall through — try next provider
            }
        }

        // 2. Apple Intelligence (silent, iOS 26+, no user-facing provider choice)
        if AppleIntelligenceService.isAvailable {
            if let result = try? await appleIntelligence.parse(transcript: transcript) {
                lastProvider = "appleIntelligence"
                return result
            }
            appleIntelligenceFailed = true
        }

        // 3. Rule-based fallback — never throws
        lastProvider = "ruleBased"
        return byokService.parseRuleBased(transcript: transcript)
    }

    var isConfigured: Bool { openRouter.isConfigured }
}

// MARK: - AppleIntelligenceError Equatable

extension AppleIntelligenceError: Equatable {
    static func == (lhs: AppleIntelligenceError, rhs: AppleIntelligenceError) -> Bool {
        switch (lhs, rhs) {
        case (.notAvailable, .notAvailable),
             (.modelUnavailable, .modelUnavailable),
             (.invalidResponse, .invalidResponse):
            return true
        default: return false
        }
    }
}
