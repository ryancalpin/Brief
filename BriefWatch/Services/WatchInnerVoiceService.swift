// WatchInnerVoiceService.swift
// Text-to-speech for AI responses on Apple Watch

import Foundation
import AVFoundation
import WatchKit

final class WatchInnerVoiceService {

    static let shared = WatchInnerVoiceService()

    // Synced from iPhone via WatchConnectivity
    var mode: InnerVoiceMode = .hapticsOnly

    private var audioPlayer: AVAudioPlayer?
    private init() {}

    // MARK: - Speak

    // Speak on Watch.
    // .hapticsOnly → haptic feedback
    // .watchSpeaker → play synthesized audio data received from iPhone
    // .earbuds      → same as watchSpeaker but only if audio route is earbuds
    func speak(_ audioData: Data?, text: String) async {
        switch mode {
        case .hapticsOnly:
            WKInterfaceDevice.current().play(.success)

        case .watchSpeaker:
            await playAudio(audioData)

        case .earbuds:
            if earbudsConnected {
                await playAudio(audioData)
            } else {
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - Private

    private var earbudsConnected: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { $0.portType == .headphones || $0.portType == .bluetoothA2DP }
    }

    private func playAudio(_ data: Data?) async {
        guard let data else {
            WKInterfaceDevice.current().play(.success)
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
        } catch {
            WKInterfaceDevice.current().play(.success)
        }
    }
}

// InnerVoiceMode is defined in Shared/InnerVoiceMode.swift
