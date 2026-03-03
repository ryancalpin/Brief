// SettingsViewModel.swift
// Manages app settings — AI provider, API keys, permissions, defaults

import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {

    // Singleton for access by AIParsingService
    static let shared = SettingsViewModel()

    // MARK: - AI Settings

    var preferredProvider: AIProviderChoice = .appleIntelligence {
        didSet { save() }
    }

    var openAIKey: String = "" {
        didSet { saveAPIKeys() }
    }

    var anthropicKey: String = "" {
        didSet { saveAPIKeys() }
    }

    var openAIModel: String = "gpt-4o-mini" {
        didSet { save() }
    }

    // MARK: - Default Destination

    var defaultDestination: BriefDestination = .reminders {
        didSet { save() }
    }

    var autoSyncToApple: Bool = true {
        didSet { save() }
    }

    // MARK: - Interface Settings

    var hapticFeedback: Bool = true {
        didSet { save() }
    }

    var showTranscriptDuringRecording: Bool = true {
        didSet { save() }
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool = false {
        didSet { save() }
    }

    // MARK: - Persistence keys

    private enum Key {
        static let preferredProvider = "settings.preferredProvider"
        static let openAIModel       = "settings.openAIModel"
        static let defaultDest       = "settings.defaultDestination"
        static let autoSync          = "settings.autoSync"
        static let haptic            = "settings.haptic"
        static let showTranscript    = "settings.showTranscript"
        static let onboarding        = "settings.onboarding"
        // API keys go through App Group defaults (not Keychain in this sample;
        // production apps should use Keychain or SecureField with Keychain storage)
        static let openAIKey         = "settings.openAIKey"
        static let anthropicKey      = "settings.anthropicKey"
    }

    private let defaults = AppGroup.defaults

    init() {
        load()
    }

    // MARK: - Load / Save

    func load() {
        if let raw = defaults.string(forKey: Key.preferredProvider),
           let provider = AIProviderChoice(rawValue: raw) {
            preferredProvider = provider
        }
        openAIModel = defaults.string(forKey: Key.openAIModel) ?? "gpt-4o-mini"
        if let raw = defaults.string(forKey: Key.defaultDest),
           let dest = BriefDestination(rawValue: raw) {
            defaultDestination = dest
        }
        autoSyncToApple = defaults.object(forKey: Key.autoSync) as? Bool ?? true
        hapticFeedback   = defaults.object(forKey: Key.haptic) as? Bool ?? true
        showTranscriptDuringRecording = defaults.object(forKey: Key.showTranscript) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)

        // API keys (use Keychain in production)
        openAIKey    = defaults.string(forKey: Key.openAIKey) ?? ""
        anthropicKey = defaults.string(forKey: Key.anthropicKey) ?? ""
    }

    private func save() {
        defaults.set(preferredProvider.rawValue, forKey: Key.preferredProvider)
        defaults.set(openAIModel, forKey: Key.openAIModel)
        defaults.set(defaultDestination.rawValue, forKey: Key.defaultDest)
        defaults.set(autoSyncToApple, forKey: Key.autoSync)
        defaults.set(hapticFeedback, forKey: Key.haptic)
        defaults.set(showTranscriptDuringRecording, forKey: Key.showTranscript)
        defaults.set(hasCompletedOnboarding, forKey: Key.onboarding)
    }

    private func saveAPIKeys() {
        // TODO: Replace with Keychain storage in production
        defaults.set(openAIKey, forKey: Key.openAIKey)
        defaults.set(anthropicKey, forKey: Key.anthropicKey)
    }

    // MARK: - Validation

    var isOpenAIKeyValid: Bool { openAIKey.hasPrefix("sk-") && openAIKey.count > 20 }
    var isAnthropicKeyValid: Bool { anthropicKey.hasPrefix("sk-ant-") && anthropicKey.count > 20 }

    func clearAPIKey(for provider: AIProviderChoice) {
        switch provider {
        case .openAI:    openAIKey = ""
        case .anthropic: anthropicKey = ""
        default: break
        }
    }
}
