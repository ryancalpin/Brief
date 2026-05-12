// AIProcessingCoordinator.swift
// Orchestrates the 6-step processing pipeline:
//   Parse → Create BriefItem → Mirror to EventKit → Converse → Speak → Review

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AIProcessingCoordinator: @unchecked Sendable {

    // User-visible: was an error encountered during AI processing
    var processingError: Error?
    var lastProviderUsed: String = "ruleBased"

    private let aiService: AIParsingService
    private let eventKitService: EventKitService
    private let ekSyncService = EventKitSyncService()
    private let openRouter = OpenRouterService.shared
    private let innerVoice = InnerVoiceService.shared
    private let notesService: NotesExportService
    private let watchService: WatchConnectivityService
    private var modelContext: ModelContext?

    init(
        aiService: AIParsingService,
        eventKitService: EventKitService,
        notesService: NotesExportService = .init(),
        watchService: WatchConnectivityService = .shared
    ) {
        self.aiService = aiService
        self.eventKitService = eventKitService
        self.notesService = notesService
        self.watchService = watchService
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Process transcript (6-step pipeline)

    /// Processes a transcript: parses, saves, syncs, converses, speaks.
    /// Returns the created BriefItem on success, or rethrows on failure.
    /// Set isFromWatch=true when processing a transcript initiated from the Watch app.
    func processTranscript(_ transcript: String, isFromWatch: Bool = false) async throws -> BriefItem {
        processingError = nil

        // Step 1: Determine sessionID
        let sessionID = resolveSessionID()

        // Step 2: Parse transcript via AI provider chain
        let result = try await aiService.parse(transcript: transcript)
        lastProviderUsed = aiService.lastProvider

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

        // Sync with Watch, and send processing ACK if Watch-initiated
        watchService.syncRecentItems(SharedDefaults.shared.recentItems)
        if isFromWatch {
            watchService.sendProcessingResult(item.toShared())
            watchService.sendRecordingAck(success: true, message: item.title)
        }

        return item
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

    // MARK: - Apple integration

    func syncItemToNotes(_ item: BriefItem) {
        notesService.openNewNote(withTitle: item.title,
                                 body: notesService.formatNoteContent(from: item))
        item.syncedToApple = true
    }

    // MARK: - CRUD helpers

    func saveLocally(_ item: BriefItem) {
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
}
