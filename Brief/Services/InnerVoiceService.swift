// InnerVoiceService.swift
// Text-to-speech for AI responses on iOS. ElevenLabs is v1.2 — stubbed.

import Foundation
import AVFoundation
import Observation

enum InnerVoiceMode: String, CaseIterable, Codable {
    case hapticsOnly  // default — no audio
    case watchSpeaker // device speaker (on Watch: Watch built-in speaker)
    case earbuds      // earbuds when connected, else silent

    var displayName: String {
        switch self {
        case .hapticsOnly:  return "Haptics only"
        case .watchSpeaker: return "Device speaker"
        case .earbuds:      return "Earbuds when connected"
        }
    }
}

@Observable
@MainActor
final class InnerVoiceService: NSObject {

    static let shared = InnerVoiceService()

    var mode: InnerVoiceMode = .hapticsOnly

    private let synthesizer = AVSpeechSynthesizer()
    private var selectedVoiceIdentifier: String = Self.voiceMap["Calm"] ?? ""

    private override init() {
        super.init()
    }

    // MARK: - Speak

    // Speak text if mode allows audio.
    // Caps response at 300 chars, truncating at sentence boundary if possible.
    func speak(_ text: String) async {
        guard mode != .hapticsOnly else { return }

        if mode == .earbuds && !earbudsConnected { return }

        let capped = cap(text, to: 300)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
        } catch {
            return  // No audio output available; fall through silently
        }

        let utterance = AVSpeechUtterance(string: capped)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        if let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        synthesizer.speak(utterance)
    }

    func setVoice(named name: String) {
        if let identifier = Self.voiceMap[name] {
            selectedVoiceIdentifier = identifier
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Audio route

    var earbudsConnected: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { $0.portType == .headphones || $0.portType == .bluetoothA2DP }
    }

    // MARK: - Available voices (4 curated English voices for Settings UI)

    var availableVoices: [AVSpeechSynthesisVoice] {
        Self.voiceMap.compactMap { _, identifier in
            AVSpeechSynthesisVoice(identifier: identifier)
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }
    }

    // Display name → voice identifier mapping
    // Uses the closest available system voices to the curated names.
    static let voiceMap: [String: String] = [
        "Calm":   "com.apple.ttsbundle.Samantha-compact",
        "Clear":  "com.apple.ttsbundle.Alex-compact",
        "Warm":   "com.apple.ttsbundle.Victoria-compact",
        "Steady": "com.apple.ttsbundle.Fred-compact"
    ]

    static let voiceDisplayNames = ["Calm", "Clear", "Warm", "Steady"]

    // MARK: - Helpers

    private func cap(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let truncated = String(text.prefix(limit))
        // Try to break at last sentence boundary
        let sentences = truncated.components(separatedBy: ". ")
        if sentences.count > 1 {
            return sentences.dropLast().joined(separator: ". ") + "."
        }
        return truncated
    }
}
