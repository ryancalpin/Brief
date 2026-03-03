// AIParsingService.swift
// Orchestrates AI provider selection and parses voice transcripts into structured data

import Foundation
import Observation

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

    var requiresAPIKey: Bool {
        self == .openAI || self == .anthropic
    }
}

@Observable
@MainActor
final class AIParsingService {

    var isProcessing = false
    var lastError: Error?

    private let appleIntelligenceService = AppleIntelligenceService()
    private let byokService = BYOKService()

    // Injected from SettingsViewModel
    var openAIKey: String = ""
    var anthropicKey: String = ""
    var preferredProvider: AIProviderChoice = .appleIntelligence

    // MARK: - Parse

    func parse(transcript: String) async throws -> AIParseResult {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        let provider = resolveProvider()

        do {
            switch provider {
            case .appleIntelligence:
                return try await appleIntelligenceService.parse(transcript: transcript)

            case .openAI:
                guard !openAIKey.isEmpty else { throw BYOKError.invalidAPIKey("OpenAI") }
                return try await byokService.parseWithOpenAI(transcript: transcript, apiKey: openAIKey)

            case .anthropic:
                guard !anthropicKey.isEmpty else { throw BYOKError.invalidAPIKey("Anthropic") }
                return try await byokService.parseWithAnthropic(transcript: transcript, apiKey: anthropicKey)

            case .ruleBased:
                return byokService.parseRuleBased(transcript: transcript)
            }
        } catch let error as AppleIntelligenceError where error == .notAvailable {
            // Gracefully fall back if Apple Intelligence isn't available
            return await fallback(transcript: transcript)
        } catch {
            lastError = error
            // Final fallback: rule-based parser never fails
            return byokService.parseRuleBased(transcript: transcript)
        }
    }

    // MARK: - Private

    private func resolveProvider() -> AIProviderChoice {
        switch preferredProvider {
        case .appleIntelligence:
            if AppleIntelligenceService.isAvailable { return .appleIntelligence }
            return fallbackProviderIfNeeded()

        case .openAI:
            if !openAIKey.isEmpty { return .openAI }
            return fallbackProviderIfNeeded()

        case .anthropic:
            if !anthropicKey.isEmpty { return .anthropic }
            return fallbackProviderIfNeeded()

        case .ruleBased:
            return .ruleBased
        }
    }

    private func fallbackProviderIfNeeded() -> AIProviderChoice {
        if !openAIKey.isEmpty { return .openAI }
        if !anthropicKey.isEmpty { return .anthropic }
        return .ruleBased
    }

    private func fallback(transcript: String) async -> AIParseResult {
        if !openAIKey.isEmpty {
            if let result = try? await byokService.parseWithOpenAI(transcript: transcript, apiKey: openAIKey) {
                return result
            }
        }
        if !anthropicKey.isEmpty {
            if let result = try? await byokService.parseWithAnthropic(transcript: transcript, apiKey: anthropicKey) {
                return result
            }
        }
        return byokService.parseRuleBased(transcript: transcript)
    }

    // MARK: - Available providers (for Settings UI)

    var availableProviders: [AIProviderChoice] {
        var providers: [AIProviderChoice] = []
        if AppleIntelligenceService.isAvailable { providers.append(.appleIntelligence) }
        if !openAIKey.isEmpty { providers.append(.openAI) }
        if !anthropicKey.isEmpty { providers.append(.anthropic) }
        providers.append(.ruleBased)
        return providers
    }
}

extension AppleIntelligenceError: Equatable {
    static func == (lhs: AppleIntelligenceError, rhs: AppleIntelligenceError) -> Bool {
        switch (lhs, rhs) {
        case (.notAvailable, .notAvailable),
             (.modelUnavailable, .modelUnavailable),
             (.invalidResponse, .invalidResponse):
            return true
        default:
            return false
        }
    }
}
