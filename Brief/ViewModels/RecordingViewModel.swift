// RecordingViewModel.swift
// Orchestrates the full record → transcribe → parse → save flow

import Foundation
import Observation
import SwiftData
import UIKit

enum RecordingPhase {
    case idle
    case recording
    case processing
    case reviewing(BriefItem)
    case saved
    case error(Error)
}

@Observable
@MainActor
final class RecordingViewModel {

    // MARK: - State

    var phase: RecordingPhase = .idle
    var audioLevel: Float = 0
    var liveTranscript: String = ""
    var recordingDuration: Int = 0

    // MARK: - Dependencies

    private let voiceService: VoiceRecordingService
    private let aiService: AIParsingService
    private let eventKitService: EventKitService
    private let notesService: NotesExportService
    private let activityManager: RecordingActivityManager
    private let watchService: WatchConnectivityService
    private var modelContext: ModelContext?

    private var durationTimer: Timer?
    private var transcriptStream: AsyncStream<String>?

    init(
        voiceService: VoiceRecordingService,
        aiService: AIParsingService,
        eventKitService: EventKitService,
        notesService: NotesExportService = .init(),
        activityManager: RecordingActivityManager = .init(),
        watchService: WatchConnectivityService = .shared
    ) {
        self.voiceService = voiceService
        self.aiService = aiService
        self.eventKitService = eventKitService
        self.notesService = notesService
        self.activityManager = activityManager
        self.watchService = watchService
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Recording lifecycle

    func startRecording() async {
        guard phase == .idle else { return }

        // Request permissions on first use
        await voiceService.requestPermissions()
        guard voiceService.canRecord else {
            phase = .error(VoiceRecordingError.permissionDenied)
            return
        }

        do {
            phase = .recording
            activityManager.startActivity()
            startDurationTimer()

            let stream = try await voiceService.startRecording()

            if SettingsViewModel.shared.hapticFeedback {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            // Consume transcript stream
            for await partial in stream {
                liveTranscript = partial
                activityManager.updateTranscript(partial, duration: recordingDuration)
            }
        } catch {
            phase = .error(error)
            stopDurationTimer()
            activityManager.endActivity(success: false)
        }
    }

    func stopRecording() async {
        guard case .recording = phase else { return }

        stopDurationTimer()
        let finalTranscript = await voiceService.stopRecording()

        if SettingsViewModel.shared.hapticFeedback {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        guard !finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .idle
            activityManager.endActivity(success: false, finalTitle: "Nothing recorded")
            return
        }

        await processTranscript(finalTranscript)
    }

    func cancelRecording() async {
        await voiceService.cancelRecording()
        stopDurationTimer()
        phase = .idle
        liveTranscript = ""
        activityManager.endActivity(success: false)
    }

    // MARK: - Process pending transcript (from Watch or Shortcut)

    func processPendingTranscript() async {
        guard let transcript = SharedDefaults.shared.pendingTranscript,
              !transcript.isEmpty else { return }
        SharedDefaults.shared.pendingTranscript = nil
        await processTranscript(transcript)
    }

    // MARK: - AI processing

    private func processTranscript(_ transcript: String) async {
        phase = .processing
        activityManager.showProcessing()

        do {
            let result = try await aiService.parse(transcript: transcript)
            let item = result.toBriefItem(rawTranscript: transcript,
                                          aiProvider: aiService.preferredProvider.rawValue)

            // Apply user's default destination if AI returned .briefOnly and user has a preference
            if item.destinationRaw == BriefDestination.briefOnly.rawValue {
                item.destinationRaw = SettingsViewModel.shared.defaultDestination.rawValue
            }

            if SettingsViewModel.shared.autoSyncToApple {
                await syncToApple(item)
            }

            saveLocally(item)
            phase = .reviewing(item)
            activityManager.endActivity(success: true, finalTitle: item.title)
            watchService.syncRecentItems(SharedDefaults.shared.recentItems)

        } catch {
            phase = .error(error)
            activityManager.endActivity(success: false)
        }
    }

    // MARK: - Apple integration

    private func syncToApple(_ item: BriefItem) async {
        do {
            switch item.destination {
            case .reminders:
                if !eventKitService.hasRemindersAccess {
                    try await eventKitService.requestRemindersAccess()
                }
                let identifier = try await eventKitService.createReminder(from: item)
                item.externalIdentifier = identifier
                item.syncedToApple = true

            case .calendar:
                if !eventKitService.hasCalendarAccess {
                    try await eventKitService.requestCalendarAccess()
                }
                let identifier = try await eventKitService.createCalendarEvent(from: item)
                item.externalIdentifier = identifier
                item.syncedToApple = true

            case .notes:
                // Notes export happens via share sheet on user confirmation
                item.syncedToApple = false

            case .briefOnly:
                break
            }
        } catch {
            // Non-fatal: item saved locally, sync can be retried
            print("Brief: Apple sync failed: \(error)")
        }
    }

    func syncItemToNotes(_ item: BriefItem) {
        notesService.openNewNote(
            withTitle: item.title,
            body: notesService.formatNoteContent(from: item)
        )
        item.syncedToApple = true
    }

    // MARK: - Local persistence

    private func saveLocally(_ item: BriefItem) {
        modelContext?.insert(item)
        try? modelContext?.save()
        SharedDefaults.shared.addItem(item.toShared())
    }

    func deleteItem(_ item: BriefItem) {
        modelContext?.delete(item)
        try? modelContext?.save()
    }

    func toggleComplete(_ item: BriefItem) {
        item.isCompleted.toggle()
        item.updatedAt = Date()
        if let id = item.externalIdentifier, item.destination == .reminders {
            Task {
                try? await eventKitService.completeReminder(identifier: id)
            }
        }
        try? modelContext?.save()
        SharedDefaults.shared.updateItem(item.toShared())
    }

    func dismissReview() {
        phase = .idle
        liveTranscript = ""
    }

    // MARK: - Timer

    private func startDurationTimer() {
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 1
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Helpers

    var formattedDuration: String {
        String(format: "%d:%02d", recordingDuration / 60, recordingDuration % 60)
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = phase { return true }
        return false
    }
}
