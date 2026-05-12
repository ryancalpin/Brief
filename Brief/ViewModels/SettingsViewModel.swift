// SettingsViewModel.swift
// Manages app settings — AI, voice, sync, permissions

import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel: @unchecked Sendable {

    static let shared = SettingsViewModel()

    // MARK: - AI Settings

    // OpenRouter API key (BYOK mode) — stored in Keychain
    var openRouterKey: String = "" {
        didSet { KeychainService.shared.write(key: .openRouterKey, value: openRouterKey) }
    }

    var fastModel: String = "google/gemini-flash-2.5" {
        didSet { save() }
    }

    var deepModel: String = "anthropic/claude-sonnet-4-6" {
        didSet { save() }
    }

    // MARK: - Voice Responses

    var innerVoiceMode: InnerVoiceMode = .hapticsOnly {
        didSet { save(); applyInnerVoiceMode() }
    }

    var innerVoiceVoiceName: String = "Calm" {
        didSet { save(); InnerVoiceService.shared.setVoice(named: innerVoiceVoiceName) }
    }

    // MARK: - Apple Integrations

    var remindersSyncEnabled: Bool = false {
        didSet { save() }
    }

    var medicalVocabularyEnabled: Bool = false {
        didSet { save() }
    }

    // MARK: - Default Destination

    var defaultDestination: BriefDestination = .reminders {
        didSet { save() }
    }

    var autoSyncToApple: Bool = true {
        didSet { save() }
    }

    // MARK: - Interface

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
        static let fastModel          = "settings.fastModel"
        static let deepModel          = "settings.deepModel"
        static let defaultDest        = "settings.defaultDestination"
        static let autoSync           = "settings.autoSync"
        static let haptic             = "settings.haptic"
        static let showTranscript     = "settings.showTranscript"
        static let onboarding         = "settings.onboarding"
        static let innerVoiceMode     = "settings.innerVoiceMode"
        static let innerVoiceVoice    = "settings.innerVoiceVoice"
        static let reminderSync       = "settings.remindersSyncEnabled"
        static let medicalVocab       = "settings.medicalVocabulary"
    }

    private let defaults = AppGroup.defaults

    init() { load() }

    // MARK: - Load / Save

    func load() {
        // Migrate legacy API keys from UserDefaults to Keychain (one-time)
        migrateLegacyKeys()

        // Load OpenRouter key from Keychain
        openRouterKey = KeychainService.shared.read(key: .openRouterKey) ?? ""

        fastModel = defaults.string(forKey: Key.fastModel) ?? "google/gemini-flash-2.5"
        deepModel = defaults.string(forKey: Key.deepModel) ?? "anthropic/claude-sonnet-4-6"

        if let raw = defaults.string(forKey: Key.defaultDest),
           let d = BriefDestination(rawValue: raw) { defaultDestination = d }

        autoSyncToApple              = defaults.object(forKey: Key.autoSync)        as? Bool ?? true
        hapticFeedback               = defaults.object(forKey: Key.haptic)          as? Bool ?? true
        showTranscriptDuringRecording = defaults.object(forKey: Key.showTranscript) as? Bool ?? true
        hasCompletedOnboarding       = defaults.bool(forKey: Key.onboarding)
        remindersSyncEnabled         = defaults.bool(forKey: Key.reminderSync)
        medicalVocabularyEnabled     = defaults.bool(forKey: Key.medicalVocab)

        if let raw = defaults.string(forKey: Key.innerVoiceMode),
           let m = InnerVoiceMode(rawValue: raw) { innerVoiceMode = m }
        innerVoiceVoiceName = defaults.string(forKey: Key.innerVoiceVoice) ?? "Calm"

        applyInnerVoiceMode()
        InnerVoiceService.shared.setVoice(named: innerVoiceVoiceName)
    }

    private func save() {
        defaults.set(fastModel,                  forKey: Key.fastModel)
        defaults.set(deepModel,                  forKey: Key.deepModel)
        defaults.set(defaultDestination.rawValue, forKey: Key.defaultDest)
        defaults.set(autoSyncToApple,            forKey: Key.autoSync)
        defaults.set(hapticFeedback,             forKey: Key.haptic)
        defaults.set(showTranscriptDuringRecording, forKey: Key.showTranscript)
        defaults.set(hasCompletedOnboarding,     forKey: Key.onboarding)
        defaults.set(innerVoiceMode.rawValue,    forKey: Key.innerVoiceMode)
        defaults.set(innerVoiceVoiceName,        forKey: Key.innerVoiceVoice)
        defaults.set(remindersSyncEnabled,       forKey: Key.reminderSync)
        defaults.set(medicalVocabularyEnabled,   forKey: Key.medicalVocab)
    }

    // Migrate existing API keys from UserDefaults → Keychain (run once on first load)
    private func migrateLegacyKeys() {
        let legacyOAI = defaults.string(forKey: "settings.openAIKey") ?? ""
        let legacyAnt = defaults.string(forKey: "settings.anthropicKey") ?? ""
        if !legacyOAI.isEmpty {
            KeychainService.shared.write(key: .openAIKey, value: legacyOAI)
            defaults.removeObject(forKey: "settings.openAIKey")
        }
        if !legacyAnt.isEmpty {
            KeychainService.shared.write(key: .anthropicKey, value: legacyAnt)
            defaults.removeObject(forKey: "settings.anthropicKey")
        }
    }

    // MARK: - Apply settings

    private func applyInnerVoiceMode() {
        InnerVoiceService.shared.mode = innerVoiceMode
    }

    // MARK: - Validation

    var isOpenRouterKeyValid: Bool {
        !openRouterKey.isEmpty && openRouterKey.count > 10
    }

    func clearOpenRouterKey() {
        openRouterKey = ""
        KeychainService.shared.delete(key: .openRouterKey)
    }
}
