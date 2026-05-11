// SettingsView.swift
// App settings: AI, voice, Apple integrations, transcription

import SwiftUI
import EventKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsViewModel.shared
    @State private var eventKitService = EventKitService()
    @State private var showingOpenRouterKey = false

    var body: some View {
        NavigationStack {
            Form {
                aiSection
                voiceResponsesSection
                appleIntegrationsSection
                transcriptionSection
                interfaceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingOpenRouterKey) {
            OpenRouterKeySheet(key: $settings.openRouterKey)
        }
    }

    // MARK: - AI Section

    @ViewBuilder
    private var aiSection: some View {
        if APIGatewayService.isAppStoreMode {
            // App Store mode
            Section {
                LabeledContent("AI") { Text("Powered by Brief Pro") }
                    .foregroundStyle(.primary)
                Button("Manage Subscription") { /* TODO: open subscription management */ }
                    .foregroundStyle(.purple)
                TextField("Fast model", text: $settings.fastModel)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Deep model", text: $settings.deepModel)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("AI")
            } footer: {
                Text("AI is included with your Brief Pro subscription.")
            }
        } else {
            // BYOK mode
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenRouter API Key")
                        if settings.isOpenRouterKeyValid {
                            Text("Connected").font(.caption).foregroundStyle(.green)
                        } else {
                            Text("Not configured").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if settings.isOpenRouterKeyValid {
                        Button("Edit") { showingOpenRouterKey = true }.font(.subheadline)
                        Button(role: .destructive) {
                            settings.clearOpenRouterKey()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(.red)
                    } else {
                        Button("Add") { showingOpenRouterKey = true }
                            .font(.subheadline).foregroundStyle(.purple)
                    }
                }

                Link("Get a free key at openrouter.ai",
                     destination: URL(string: "https://openrouter.ai")!)
                    .font(.footnote)
                    .foregroundStyle(.purple)

                TextField("Fast model", text: $settings.fastModel)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Deep model", text: $settings.deepModel)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("AI")
            } footer: {
                Text("Your key is stored securely in the iOS Keychain and never shared.")
            }
        }
    }

    // MARK: - Voice Responses

    private var voiceResponsesSection: some View {
        Section("Voice Responses") {
            Picker("Response mode", selection: $settings.innerVoiceMode) {
                ForEach(InnerVoiceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Voice", selection: $settings.innerVoiceVoiceName) {
                ForEach(InnerVoiceService.voiceDisplayNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .disabled(settings.innerVoiceMode == .hapticsOnly)

            HStack {
                Text("ElevenLabs Voice Clone")
                Spacer()
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Apple Integrations

    private var appleIntegrationsSection: some View {
        Section {
            Toggle(isOn: $settings.remindersSyncEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync with Apple Reminders")
                    Text("Your todos are always saved in Brief. Turn this on to also add them to Apple Reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.remindersSyncEnabled) { _, enabled in
                if enabled {
                    Task { try? await eventKitService.requestRemindersAccess() }
                }
            }

            HStack {
                Text("Sync with Apple Calendar")
                Spacer()
                Text("Coming soon").font(.caption).foregroundStyle(.tertiary)
            }

            HStack {
                Text("Sync with Apple Notes")
                Spacer()
                Text("Coming soon").font(.caption).foregroundStyle(.tertiary)
            }
        } header: {
            Text("Apple Integrations")
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        Section {
            Toggle(isOn: $settings.medicalVocabularyEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Medical vocabulary")
                    Text("Uses a medical-grade speech model. Improves accuracy for clinical terms, drug names, and abbreviations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // TODO: Wire WhisperKit + Whisper-Medical model in v1.1
        } header: {
            Text("Transcription")
        } footer: {
            Text("Medical transcription with WhisperKit is coming in v1.1.")
        }
    }

    // MARK: - Interface

    private var interfaceSection: some View {
        Section("Interface") {
            Toggle("Haptic Feedback", isOn: $settings.hapticFeedback)
            Toggle("Show transcript while recording", isOn: $settings.showTranscriptDuringRecording)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
    }
}

// MARK: - OpenRouter Key Sheet

struct OpenRouterKeySheet: View {
    @Binding var key: String
    @Environment(\.dismiss) private var dismiss
    @State private var localKey: String = ""
    @State private var isVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Group {
                            if isVisible {
                                TextField("sk-or-...", text: $localKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("sk-or-...", text: $localKey)
                            }
                        }
                        Button { isVisible.toggle() } label: {
                            Image(systemName: isVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Get a free key at openrouter.ai — your key is stored securely in the iOS Keychain.")
                }
            }
            .navigationTitle("OpenRouter API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { key = localKey; dismiss() }
                        .disabled(localKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { localKey = key }
        }
    }
}
