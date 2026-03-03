// BriefApp.swift
// App entry point — wires up SwiftData, environment objects, and onboarding

import SwiftUI
import SwiftData

@main
struct BriefApp: App {

    // MARK: - SwiftData container

    let modelContainer: ModelContainer = {
        let schema = Schema([BriefItem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic  // iCloud sync via CloudKit
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Brief: Failed to create ModelContainer: \(error)")
        }
    }()

    // MARK: - Services (shared across the app)

    @State private var voiceService = VoiceRecordingService()
    @State private var aiService = AIParsingService()
    @State private var eventKitService = EventKitService()
    @State private var recordingVM: RecordingViewModel
    @State private var watchService = WatchConnectivityService.shared

    // Onboarding
    @State private var showOnboarding = !SettingsViewModel.shared.hasCompletedOnboarding

    init() {
        // Wire up AI service with settings
        let ai = AIParsingService()
        let settings = SettingsViewModel.shared
        ai.openAIKey = settings.openAIKey
        ai.anthropicKey = settings.anthropicKey
        ai.preferredProvider = settings.preferredProvider

        let eventKit = EventKitService()
        let voice = VoiceRecordingService()

        _voiceService = State(initialValue: voice)
        _aiService = State(initialValue: ai)
        _eventKitService = State(initialValue: eventKit)
        _recordingVM = State(initialValue: RecordingViewModel(
            voiceService: voice,
            aiService: ai,
            eventKitService: eventKit
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(recordingVM: recordingVM)
                .modelContainer(modelContainer)
                .environment(voiceService)
                .environment(aiService)
                .environment(eventKitService)
                .environment(watchService)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
                .onAppear {
                    watchService.activate()
                    syncSettingsToServices()
                }
                .onChange(of: SettingsViewModel.shared.openAIKey) {
                    aiService.openAIKey = SettingsViewModel.shared.openAIKey
                }
                .onChange(of: SettingsViewModel.shared.anthropicKey) {
                    aiService.anthropicKey = SettingsViewModel.shared.anthropicKey
                }
                .onChange(of: SettingsViewModel.shared.preferredProvider) {
                    aiService.preferredProvider = SettingsViewModel.shared.preferredProvider
                }
                .onReceive(NotificationCenter.default.publisher(for: .briefProcessPendingTranscript)) { _ in
                    Task { await recordingVM.processPendingTranscript() }
                }
                // Handle Watch-initiated transcript processing
                .onChange(of: watchService.watchRequestedProcessing) { _, newValue in
                    if newValue {
                        Task {
                            await recordingVM.processPendingTranscript()
                            watchService.watchRequestedProcessing = false
                        }
                    }
                }
        }
    }

    private func syncSettingsToServices() {
        let settings = SettingsViewModel.shared
        aiService.openAIKey = settings.openAIKey
        aiService.anthropicKey = settings.anthropicKey
        aiService.preferredProvider = settings.preferredProvider
    }
}

// MARK: - Root content view

struct ContentView: View {
    let recordingVM: RecordingViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HomeView(recordingVM: recordingVM)
            .task {
                recordingVM.setModelContext(modelContext)
            }
    }
}
