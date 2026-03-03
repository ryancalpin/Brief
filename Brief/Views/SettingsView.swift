// SettingsView.swift
// App settings: AI provider, API keys, permissions, defaults

import SwiftUI
import EventKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsViewModel.shared
    @State private var eventKitService = EventKitService()
    @State private var showingOpenAIKey = false
    @State private var showingAnthropicKey = false
    @State private var appleIntelligenceStatus = AppleIntelligenceService.availabilityStatus

    var body: some View {
        NavigationStack {
            Form {
                // AI Provider section
                Section {
                    Picker("AI Provider", selection: $settings.preferredProvider) {
                        ForEach(AIProviderChoice.allCases, id: \.self) { provider in
                            HStack {
                                Text(provider.displayName)
                                if provider == .appleIntelligence && appleIntelligenceStatus != .available {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .tag(provider)
                        }
                    }

                    if appleIntelligenceStatus != .available {
                        AppleIntelligenceStatusRow(status: appleIntelligenceStatus)
                    }
                } header: {
                    Text("AI Processing")
                } footer: {
                    Text("Apple Intelligence uses on-device AI for maximum privacy. BYOK uses cloud APIs.")
                }

                // BYOK API Keys
                Section("API Keys") {
                    // OpenAI
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OpenAI Key")
                            if settings.isOpenAIKeyValid {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if !settings.openAIKey.isEmpty {
                                Text("Invalid format")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if settings.openAIKey.isEmpty {
                            Button("Add") { showingOpenAIKey = true }
                                .font(.subheadline)
                        } else {
                            Button("Edit") { showingOpenAIKey = true }
                                .font(.subheadline)
                            Button(role: .destructive) {
                                settings.clearAPIKey(for: .openAI)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    // Anthropic
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anthropic Key")
                            if settings.isAnthropicKeyValid {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if !settings.anthropicKey.isEmpty {
                                Text("Invalid format")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if settings.anthropicKey.isEmpty {
                            Button("Add") { showingAnthropicKey = true }
                                .font(.subheadline)
                        } else {
                            Button("Edit") { showingAnthropicKey = true }
                                .font(.subheadline)
                            Button(role: .destructive) {
                                settings.clearAPIKey(for: .anthropic)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    Picker("OpenAI Model", selection: $settings.openAIModel) {
                        Text("GPT-4o Mini (Fast)").tag("gpt-4o-mini")
                        Text("GPT-4o (Smart)").tag("gpt-4o")
                    }
                    .disabled(!settings.isOpenAIKeyValid)
                }

                // Permissions
                Section("Permissions") {
                    PermissionRow(
                        title: "Reminders",
                        icon: "checklist",
                        status: eventKitService.remindersAuthStatus,
                        onRequest: {
                            Task { try? await eventKitService.requestRemindersAccess() }
                        }
                    )
                    PermissionRow(
                        title: "Calendar",
                        icon: "calendar",
                        status: eventKitService.calendarAuthStatus,
                        onRequest: {
                            Task { try? await eventKitService.requestCalendarAccess() }
                        }
                    )
                }

                // Defaults
                Section("Defaults") {
                    Picker("Default Destination", selection: $settings.defaultDestination) {
                        ForEach(BriefDestination.allCases, id: \.self) { dest in
                            Label(dest.displayName, systemImage: dest.systemImage)
                                .tag(dest)
                        }
                    }
                    Toggle("Auto-sync to Apple apps", isOn: $settings.autoSyncToApple)
                }

                // Interface
                Section("Interface") {
                    Toggle("Haptic Feedback", isOn: $settings.hapticFeedback)
                    Toggle("Show transcript while recording", isOn: $settings.showTranscriptDuringRecording)
                }

                // About
                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    }
                    Link("Privacy Policy", destination: URL(string: "https://brief.app/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://brief.app/terms")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingOpenAIKey) {
            APIKeySheet(
                title: "OpenAI API Key",
                placeholder: "sk-...",
                key: $settings.openAIKey,
                instructions: "Get your key at platform.openai.com"
            )
        }
        .sheet(isPresented: $showingAnthropicKey) {
            APIKeySheet(
                title: "Anthropic API Key",
                placeholder: "sk-ant-...",
                key: $settings.anthropicKey,
                instructions: "Get your key at console.anthropic.com"
            )
        }
    }
}

// MARK: - Supporting Views

struct AppleIntelligenceStatusRow: View {
    let status: AppleIntelligenceService.AvailabilityStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusTitle: String {
        switch status {
        case .available:                return ""
        case .requiresiOS26:            return "Requires iOS 26"
        case .appleIntelligenceDisabled: return "Apple Intelligence Disabled"
        case .modelUnavailable:         return "Model Unavailable"
        }
    }

    private var statusMessage: String {
        switch status {
        case .available:
            return ""
        case .requiresiOS26:
            return "Update to iOS 26 to use on-device AI. BYOK is available now."
        case .appleIntelligenceDisabled:
            return "Enable Apple Intelligence in Settings → Apple Intelligence & Siri."
        case .modelUnavailable:
            return "The language model is currently downloading or unavailable."
        }
    }
}

struct PermissionRow: View {
    let title: String
    let icon: String
    let status: EKAuthorizationStatus
    let onRequest: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            permissionButton
        }
    }

    @ViewBuilder
    private var permissionButton: some View {
        switch status {
        case .fullAccess:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .denied:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
        default:
            Button("Allow", action: onRequest)
                .font(.subheadline)
                .foregroundStyle(.purple)
        }
    }
}

struct APIKeySheet: View {
    let title: String
    let placeholder: String
    @Binding var key: String
    let instructions: String
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
                                TextField(placeholder, text: $localKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField(placeholder, text: $localKey)
                            }
                        }
                        Button {
                            isVisible.toggle()
                        } label: {
                            Image(systemName: isVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(instructions)
                }

                Section {
                    Text("API keys are stored locally on your device and never shared with Anthropic or anyone else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        key = localKey
                        dismiss()
                    }
                    .disabled(localKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { localKey = key }
        }
    }
}
