// RecordingViewModel.swift
// Public facade — delegates to RecordingCoordinator, AIProcessingCoordinator,
// and AppleSyncCoordinator for a clean separation of concerns.

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
final class RecordingViewModel: @unchecked Sendable {

    // MARK: - Coordinators

    let recording: RecordingCoordinator
    let processing: AIProcessingCoordinator
    let sync: AppleSyncCoordinator

    // MARK: - State (forwarded from recording coordinator)

    var phase: RecordingPhase { recording.phase }
    var audioLevel: Float { recording.audioLevel }
    var liveTranscript: String { recording.liveTranscript }
    var recordingDuration: Int { recording.recordingDuration }

    // MARK: - Init

    init(
        voiceService: VoiceRecordingService,
        aiService: AIParsingService,
        eventKitService: EventKitService,
        notesService: NotesExportService = .init(),
        activityManager: RecordingActivityManager = .init(),
        watchService: WatchConnectivityService = .shared
    ) {
        self.recording = RecordingCoordinator(
            voiceService: voiceService,
            activityManager: activityManager
        )
        self.processing = AIProcessingCoordinator(
            aiService: aiService,
            eventKitService: eventKitService,
            notesService: notesService,
            watchService: watchService
        )
        self.sync = AppleSyncCoordinator(
            eventKitService: eventKitService,
            watchService: watchService
        )
    }

    func setModelContext(_ context: ModelContext) {
        processing.setModelContext(context)
        sync.setModelContext(context)
    }

    // MARK: - Recording lifecycle

    func startRecording() async {
        await recording.startRecording()
    }

    func stopRecording() async {
        guard let transcript = await recording.stopRecording() else { return }
        await processTranscript(transcript)
    }

    func cancelRecording() async {
        await recording.cancelRecording()
    }

    // MARK: - Process pending transcript (from Watch or Shortcut)

    func processPendingTranscript() async {
        guard let transcript = SharedDefaults.shared.pendingTranscript,
              !transcript.isEmpty else { return }
        SharedDefaults.shared.pendingTranscript = nil
        await processTranscript(transcript, isFromWatch: true)
    }

    // MARK: - AI Processing

    private func processTranscript(_ transcript: String, isFromWatch: Bool = false) async {
        recording.setProcessing()

        do {
            let item = try await processing.processTranscript(transcript, isFromWatch: isFromWatch)
            recording.phase = .reviewing(item)
        } catch {
            recording.phase = .error(error)
            if isFromWatch {
                // Send failure ACK back to Watch
                WatchConnectivityService.shared.sendRecordingAck(
                    success: false,
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Apple integration

    func syncItemToNotes(_ item: BriefItem) {
        processing.syncItemToNotes(item)
    }

    // MARK: - CRUD

    func deleteItem(_ item: BriefItem) {
        sync.deleteMirroredItem(item)
        processing.deleteItem(item)
    }

    func toggleComplete(_ item: BriefItem) {
        sync.toggleComplete(item)
    }

    func applyCompletionSideEffects(_ item: BriefItem) {
        sync.applyCompletionSideEffects(item)
    }

    func dismissReview() {
        recording.dismissReview()
    }

    // MARK: - Helpers

    var formattedDuration: String { recording.formattedDuration }
    var isRecording: Bool { recording.isRecording }
    var isProcessing: Bool { recording.isProcessing }
}
