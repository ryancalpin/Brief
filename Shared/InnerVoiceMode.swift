// InnerVoiceMode.swift
// Shared between iOS and watchOS targets so the enum has one definition.

import Foundation

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
