// BriefItem.swift
// Primary SwiftData model for the iOS App target

import Foundation
import SwiftData

@Model
final class BriefItem {
    var id: UUID
    var rawTranscript: String
    var title: String
    var content: String?
    var itemTypeRaw: String
    var destinationRaw: String
    var createdAt: Date
    var updatedAt: Date
    var isCompleted: Bool
    var isProcessed: Bool           // AI has processed it
    var externalIdentifier: String? // EventKit EKReminder/EKEvent identifier, or Notes URL
    var syncedToApple: Bool         // True once pushed to Reminders/Calendar/Notes

    // Reminder fields
    var dueDate: Date?
    var priorityRaw: String?

    // Calendar event fields
    var startDate: Date?
    var endDate: Date?
    var location: String?

    // Metadata
    var tags: [String]
    var aiProviderUsed: String?

    init(
        rawTranscript: String,
        title: String,
        content: String? = nil,
        itemType: BriefItemType,
        destination: BriefDestination,
        dueDate: Date? = nil,
        priority: BriefPriority? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        location: String? = nil,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.rawTranscript = rawTranscript
        self.title = title
        self.content = content
        self.itemTypeRaw = itemType.rawValue
        self.destinationRaw = destination.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isCompleted = false
        self.isProcessed = false
        self.syncedToApple = false
        self.dueDate = dueDate
        self.priorityRaw = priority?.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.tags = tags
    }

    var itemType: BriefItemType {
        BriefItemType(rawValue: itemTypeRaw) ?? .generic
    }

    var destination: BriefDestination {
        BriefDestination(rawValue: destinationRaw) ?? .briefOnly
    }

    var priority: BriefPriority? {
        priorityRaw.flatMap { BriefPriority(rawValue: $0) }
    }

    func toShared() -> SharedBriefItem {
        SharedBriefItem(
            id: id,
            title: title,
            content: content,
            itemTypeRaw: itemTypeRaw,
            destinationRaw: destinationRaw,
            createdAt: createdAt,
            isCompleted: isCompleted,
            dueDate: dueDate,
            tags: tags
        )
    }
}

// MARK: - Enums (defined here for iOS target; SharedBriefItem.SharedItemType is for cross-target use)

enum BriefItemType: String, CaseIterable {
    case reminder
    case note
    case calendarEvent = "calendarEvent"
    case list
    case generic

    var displayName: String {
        switch self {
        case .reminder:      return "Reminder"
        case .note:          return "Note"
        case .calendarEvent: return "Calendar Event"
        case .list:          return "List"
        case .generic:       return "Item"
        }
    }

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

enum BriefDestination: String, CaseIterable {
    case reminders
    case notes
    case calendar
    case briefOnly

    var displayName: String {
        switch self {
        case .reminders:  return "Reminders"
        case .notes:      return "Notes"
        case .calendar:   return "Calendar"
        case .briefOnly:  return "Brief Only"
        }
    }

    var systemImage: String {
        switch self {
        case .reminders:  return "checklist.checked"
        case .notes:      return "note.text"
        case .calendar:   return "calendar.badge.plus"
        case .briefOnly:  return "star.fill"
        }
    }
}

enum BriefPriority: String, CaseIterable {
    case low, medium, high, urgent

    var displayName: String { rawValue.capitalized }

    var eventKitPriority: Int {
        switch self {
        case .low:    return 9
        case .medium: return 5
        case .high:   return 3
        case .urgent: return 1
        }
    }
}
