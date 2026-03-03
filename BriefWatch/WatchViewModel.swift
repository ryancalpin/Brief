// WatchViewModel.swift
// Orchestrates Watch recording → send to iPhone flow

import Foundation
import Combine

enum WatchRecordingPhase {
    case idle
    case recording
    case sending           // Transcript sent to iPhone
    case waitingForResult  // iPhone processing
    case done(SharedBriefItem)
    case error(Error)
}

@MainActor
final class WatchViewModel: ObservableObject {

    @Published var phase: WatchRecordingPhase = .idle
    @Published var liveTranscript = ""
    @Published var duration = 0

    private let voiceService = WatchVoiceService()
    private let connectivity = WatchConnectivityHandler.shared
    private var durationTimer: Timer?
    private var resultCancellable: AnyCancellable?

    // MARK: - Recording

    func startRecording() async {
        await voiceService.requestPermissions()
        guard voiceService.canRecord else {
            phase = .error(WatchVoiceError.permissionDenied)
            return
        }

        do {
            phase = .recording
            duration = 0
            startTimer()
            try await voiceService.startRecording()

            // Mirror live transcript
            for await _ in AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1)).stream {
                liveTranscript = voiceService.liveTranscript
            }
        } catch {
            phase = .error(error)
        }
    }

    func stopRecording() async {
        stopTimer()
        let transcript = await voiceService.stopRecording()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .idle
            return
        }

        phase = .sending
        liveTranscript = transcript
        sendToiPhone(transcript)
    }

    func cancel() async {
        stopTimer()
        await voiceService.stopRecording()
        phase = .idle
        liveTranscript = ""
    }

    // MARK: - Send to iPhone

    private func sendToiPhone(_ transcript: String) {
        connectivity.sendTranscript(transcript)
        phase = .waitingForResult

        // Watch for result via WatchConnectivityHandler
        resultCancellable = connectivity.$lastProcessingResult
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.phase = .done(item)
                self?.resultCancellable = nil
            }

        // Timeout after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            if case .waitingForResult = self.phase {
                self.phase = .error(WatchError.timeout)
                self.resultCancellable = nil
            }
        }
    }

    func dismiss() {
        phase = .idle
        liveTranscript = ""
    }

    // MARK: - Timer

    private func startTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.duration += 1 }
        }
    }

    private func stopTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    var formattedDuration: String {
        String(format: "%d:%02d", duration / 60, duration % 60)
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }
}

enum WatchError: LocalizedError {
    case timeout
    var errorDescription: String? { "iPhone didn't respond in time. Check your connection." }
}
