// VoiceRecordingService.swift
// Manages microphone + real-time speech recognition using Speech framework

import Foundation
import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceRecordingService: NSObject {

    // MARK: - Observable state

    var isRecording = false
    var liveTranscript = ""
    var speechAuthStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var micAuthStatus: AVAudioApplication.RecordPermission = .undetermined
    var audioLevel: Float = 0.0   // 0.0 – 1.0 for waveform UI
    var error: VoiceRecordingError?

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var levelTimer: Timer?

    // MARK: - Permissions

    func requestPermissions() async {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        speechAuthStatus = speechStatus

        let micGranted = await AVAudioApplication.requestRecordPermission()
        micAuthStatus = micGranted ? .granted : .denied
    }

    var canRecord: Bool {
        speechAuthStatus == .authorized && micAuthStatus == .granted
    }

    // MARK: - Recording lifecycle

    /// Starts recording and returns a stream of partial transcripts.
    func startRecording() async throws -> AsyncStream<String> {
        guard canRecord else {
            throw VoiceRecordingError.permissionDenied
        }
        guard !isRecording else {
            throw VoiceRecordingError.alreadyRecording
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceRecordingError.recognizerUnavailable
        }

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true     // Privacy-first: on-device only
        request.addsPunctuation = true
        recognitionRequest = request

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.liveTranscript = transcript
                }
                continuation.yield(transcript)
                if result.isFinal {
                    continuation.finish()
                }
            }
            if let error {
                let nsError = error as NSError
                // Code 1110 = no speech detected — not a fatal error
                if nsError.code != 1110 {
                    Task { @MainActor in
                        self.error = .recognitionFailed(error.localizedDescription)
                    }
                    continuation.finish()
                }
            }
        }

        // Tap the input node
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            // Compute RMS level for waveform visualisation
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            guard let data = channelData, frameLength > 0 else { return }
            let rms = sqrt((0..<frameLength).reduce(Float(0)) { $0 + data[$1] * data[$1] } / Float(frameLength))
            Task { @MainActor in
                self?.audioLevel = min(rms * 10, 1.0)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw VoiceRecordingError.audioEngineFailed(error.localizedDescription)
        }

        isRecording = true
        SharedDefaults.shared.isRecording = true
        return stream
    }

    /// Stops recording and returns the final transcript.
    @discardableResult
    func stopRecording() async -> String {
        guard isRecording else { return "" }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let final = liveTranscript
        isRecording = false
        liveTranscript = ""
        audioLevel = 0
        SharedDefaults.shared.isRecording = false
        recognitionRequest = nil
        recognitionTask = nil
        return final
    }

    func cancelRecording() async {
        recognitionTask?.cancel()
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        liveTranscript = ""
        audioLevel = 0
        SharedDefaults.shared.isRecording = false
        recognitionRequest = nil
        recognitionTask = nil
    }
}

// MARK: - Errors

enum VoiceRecordingError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case recognizerUnavailable
    case audioEngineFailed(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition permission is required. Please enable in Settings."
        case .alreadyRecording:
            return "Recording is already in progress."
        case .recognizerUnavailable:
            return "Speech recognizer is not available. Check your network connection or try again."
        case .audioEngineFailed(let msg):
            return "Audio engine failed to start: \(msg)"
        case .recognitionFailed(let msg):
            return "Speech recognition error: \(msg)"
        }
    }
}
