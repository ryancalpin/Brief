// AppGroupConstants.swift
// Shared constants for App Group communication between iOS app, Widget, and Watch targets

import Foundation

enum AppGroup {
    static let identifier = "group.com.brief.app"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier)!
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

enum AppGroupKey {
    static let recentItems      = "recentItems"       // [SharedBriefItem] encoded JSON
    static let lastUpdated      = "lastUpdated"       // Date
    static let aiProvider       = "aiProvider"        // String
    static let openAIKey        = "openAIKey"         // String (stored in Keychain in production)
    static let anthropicKey     = "anthropicKey"      // String
    static let recordingState   = "recordingState"    // Bool
    static let pendingTranscript = "pendingTranscript" // String (Watch → iPhone handoff)
    static let watchLastSync    = "watchLastSync"     // Date
}

/// Lightweight model used across all targets (no SwiftData dependency)
struct SharedBriefItem: Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var content: String?
    var itemTypeRaw: String
    var destinationRaw: String
    var createdAt: Date
    var isCompleted: Bool
    var dueDate: Date?
    var tags: [String]

    var itemType: SharedItemType { SharedItemType(rawValue: itemTypeRaw) ?? .generic }
    var destination: SharedDestination { SharedDestination(rawValue: destinationRaw) ?? .briefOnly }

    enum SharedItemType: String, Codable, CaseIterable {
        case reminder, note, calendarEvent, list, generic
        var systemImage: String {
            switch self {
            case .reminder:      return "checklist"
            case .note:          return "note.text"
            case .calendarEvent: return "calendar"
            case .list:          return "list.bullet"
            case .generic:       return "sparkles"
            }
        }
    }

    enum SharedDestination: String, Codable, CaseIterable {
        case reminders, notes, calendar, briefOnly
        var displayName: String {
            switch self {
            case .reminders:  return "Reminders"
            case .notes:      return "Notes"
            case .calendar:   return "Calendar"
            case .briefOnly:  return "Brief"
            }
        }
    }
}
