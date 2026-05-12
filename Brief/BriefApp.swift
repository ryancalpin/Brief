// BriefApp.swift
// App entry point — wires up SwiftData, environment objects, and onboarding

import SwiftUI
import SwiftData

@main
struct BriefApp: App {

    // MARK: - SwiftData container

    let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: BriefSchemaV1.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic  // iCloud sync via CloudKit
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BriefMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // Fall back to in-memory store if persistent store fails.
            // On first launch after iCloud switch or during data corruption
            // recovery, this prevents a crash and lets the user continue.
            let memoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            guard let container = try? ModelContainer(
                for: schema,
                migrationPlan: BriefMigrationPlan.self,
                configurations: [memoryConfig]
            ) else {
                // Absolute last resort — can't even create in-memory store.
                // This should never happen in practice.
                let errSchema = Schema([BriefItem.self])
                return try! ModelContainer(for: errSchema)
            }
            return container
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
        let ai = AIParsingService()
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
