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
    private let ekSyncService = EventKitSyncService()
    private let openRouter = OpenRouterService.shared
    private let innerVoice = InnerVoiceService.shared
    private let notesService: NotesExportService
    private let activityManager: RecordingActivityManager
    private let watchService: WatchConnectivityService
    private var modelContext: ModelContext?

    private var durationTimer: Timer?

    init(
        voiceService: VoiceRecordingService,
        aiService: AIParsingService,
        eventKitService: EventKitService,
        notesService: NotesExportService = .init(),
        activityManager: RecordingActivityManager = .init(),
        watchService: WatchConnectivityService = .shared
    ) {
        self.voiceService    = voiceService
        self.aiService       = aiService
        self.eventKitService = eventKitService
        self.notesService    = notesService
        self.activityManager = activityManager
        self.watchService    = watchService
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Recording lifecycle

    func startRecording() async {
        guard case .idle = phase else { return }
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

    // MARK: - AI processing (6-step flow)

    private func processTranscript(_ transcript: String) async {
        phase = .processing
        activityManager.showProcessing()

        do {
            // Step 1: Determine sessionID
            let sessionID = resolveSessionID()

            // Step 2: Parse transcript
            let result = try await aiService.parse(transcript: transcript)

            // Step 3: Create BriefItem, set sessionID, save to SwiftData
            let item = result.toBriefItem(rawTranscript: transcript,
                                          aiProvider: aiService.lastProvider)
            item.sessionID = sessionID
            saveLocally(item)

            // Step 4: Mirror to Apple Reminders if enabled
            let settings = SettingsViewModel.shared
            if result.itemType == .reminder && settings.remindersSyncEnabled {
                item.ekSyncEnabled = true
                if let ctx = modelContext {
                    try? await ekSyncService.mirror(item, context: ctx)
                }
            }

            // Step 5: Conversational reply if isConversational and OpenRouter configured
            if result.isConversational && openRouter.isConfigured {
                let history = buildConvoHistory(sessionID: sessionID, excluding: item)
                if let reply = try? await openRouter.converse(
                    history: history,
                    newMessage: transcript
                ) {
                    item.aiResponse = reply
                    try? modelContext?.save()
                }
            }

            // Step 6: Speak response via InnerVoiceService
            let textToSpeak = item.aiResponse ?? confirmationPhrase(for: result.itemType)
            await innerVoice.speak(textToSpeak)

            phase = .reviewing(item)
            activityManager.endActivity(success: true, finalTitle: item.title)
            watchService.syncRecentItems(SharedDefaults.shared.recentItems)

        } catch {
            phase = .error(error)
            activityManager.endActivity(success: false)
        }
    }

    // MARK: - Session ID

    private func resolveSessionID() -> UUID {
        guard let ctx = modelContext else { return UUID() }
        let descriptor = FetchDescriptor<BriefItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let recent = (try? ctx.fetch(descriptor))?.first
        if let last = recent,
           Date().timeIntervalSince(last.createdAt) < 5 * 60,
           let sid = last.sessionID {
            return sid
        }
        return UUID()
    }

    // MARK: - Conversation history

    private func buildConvoHistory(sessionID: UUID, excluding item: BriefItem) -> [ConvoMessage] {
        guard let ctx = modelContext else { return [] }
        var descriptor = FetchDescriptor<BriefItem>(
            predicate: #Predicate { $0.itemTypeRaw == "convo" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 10
        let allConvo = (try? ctx.fetch(descriptor)) ?? []
        let sessionItems = allConvo.filter { $0.sessionID == sessionID && $0.id != item.id }
        let last5 = Array(sessionItems.suffix(5))
        return last5.flatMap { convoItem -> [ConvoMessage] in
            var msgs: [ConvoMessage] = [
                ConvoMessage(role: "user", content: convoItem.rawTranscript)
            ]
            if let reply = convoItem.aiResponse {
                msgs.append(ConvoMessage(role: "assistant", content: reply))
            }
            return msgs
        }
    }

    // MARK: - Confirmation phrases

    private func confirmationPhrase(for itemType: BriefItemType) -> String {
        switch itemType {
        case .reminder:      return "Reminder saved."
        case .note:          return "Note captured."
        case .calendarEvent: return "Calendar event saved."
        case .list:          return "List saved."
        case .convo:         return "Got it."
        case .generic:       return "Item captured."
        }
    }

    // MARK: - Apple integration (legacy path — used by manual sync actions)

    func syncItemToNotes(_ item: BriefItem) {
        notesService.openNewNote(withTitle: item.title,
                                 body: notesService.formatNoteContent(from: item))
        item.syncedToApple = true
    }

    // MARK: - Local persistence

    private func saveLocally(_ item: BriefItem) {
        modelContext?.insert(item)
        try? modelContext?.save()
        SharedDefaults.shared.addItem(item.toShared())
    }

    func deleteItem(_ item: BriefItem) {
        if item.ekSyncEnabled, let _ = item.ekIdentifier {
            Task { try? await ekSyncService.delete(item) }
        }
        modelContext?.delete(item)
        try? modelContext?.save()
    }

    func toggleComplete(_ item: BriefItem) {
        item.isCompleted.toggle()
        applyCompletionSideEffects(item)
    }

    // Use this when the Toggle binding has already mutated isCompleted —
    // it skips the toggle and only runs the side effects (sync, persistence, etc.).
    func applyCompletionSideEffects(_ item: BriefItem) {
        item.updatedAt = Date()
        if item.isCompleted { item.completedAt = Date() }
        else                { item.completedAt = nil }
        if item.ekIdentifier != nil, item.ekSyncEnabled {
            Task { try? await ekSyncService.complete(item) }
        } else if let id = item.externalIdentifier, item.destination == .reminders {
            Task { try? await eventKitService.completeReminder(identifier: id) }
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
            Task { @MainActor in self?.recordingDuration += 1 }
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
