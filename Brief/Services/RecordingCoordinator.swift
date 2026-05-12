// RecordingCoordinator.swift
// Handles the recording lifecycle: start, stop, cancel, timer, transcript streaming

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class RecordingCoordinator: @unchecked Sendable {

    // MARK: - Observable state

    var phase: RecordingPhase = .idle
    var audioLevel: Float = 0
    var liveTranscript: String = ""
    var recordingDuration: Int = 0

    // MARK: - Dependencies

    private let voiceService: VoiceRecordingService
    private let activityManager: RecordingActivityManager
    private var durationTimer: Timer?

    init(
        voiceService: VoiceRecordingService,
        activityManager: RecordingActivityManager = .init()
    ) {
        self.voiceService = voiceService
        self.activityManager = activityManager
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

    /// Stops recording, returns the final transcript and sets phase to .processing.
    /// Returns nil if transcript is empty (phase reset to .idle).
    func stopRecording() async -> String? {
        guard case .recording = phase else { return nil }
        stopDurationTimer()
        let finalTranscript = await voiceService.stopRecording()
        if SettingsViewModel.shared.hapticFeedback {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        guard !finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .idle
            activityManager.endActivity(success: false, finalTitle: "Nothing recorded")
            return nil
        }
        return finalTranscript
    }

    func cancelRecording() async {
        await voiceService.cancelRecording()
        stopDurationTimer()
        phase = .idle
        liveTranscript = ""
        activityManager.endActivity(success: false)
    }

    func setProcessing() {
        phase = .processing
        activityManager.showProcessing()
    }

    func setPhase(_ newPhase: RecordingPhase) {
        phase = newPhase
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
