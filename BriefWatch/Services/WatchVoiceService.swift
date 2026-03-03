// WatchVoiceService.swift
// Voice recording and transcription on Apple Watch (standalone, no iPhone required)

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class WatchVoiceService: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var error: Error?

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: .current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Permissions

    func requestPermissions() async {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { s in cont.resume(returning: s) }
        }
        authStatus = status
    }

    var canRecord: Bool {
        authStatus == .authorized && recognizer != nil
    }

    // MARK: - Record

    func startRecording() async throws {
        guard canRecord, !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw WatchVoiceError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true   // Watch always uses on-device
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.liveTranscript = result.bestTranscription.formattedString
                }
            }
            if let error {
                Task { @MainActor in
                    self.error = error
                }
            }
        }

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.recognitionRequest?.append(buf)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    @discardableResult
    func stopRecording() async -> String {
        guard isRecording else { return "" }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        try? AVAudioSession.sharedInstance().setActive(false)
        let final = liveTranscript
        isRecording = false
        liveTranscript = ""
        recognitionRequest = nil
        recognitionTask = nil
        return final
    }
}

enum WatchVoiceError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer not available on Watch."
        case .permissionDenied: return "Microphone permission required."
        }
    }
}
