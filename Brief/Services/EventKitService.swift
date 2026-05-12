// EventKitService.swift
// Creates and manages Reminders and Calendar events via EventKit

import Foundation
import EventKit
import Observation

@Observable
@MainActor
final class EventKitService: @unchecked Sendable {

    var remindersAuthStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    var calendarAuthStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()

    // MARK: - Permissions

    func requestRemindersAccess() async throws {
        let granted = try await store.requestFullAccessToReminders()
        remindersAuthStatus = granted ? .fullAccess : .denied
    }

    func requestCalendarAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        calendarAuthStatus = granted ? .fullAccess : .denied
    }

    var hasRemindersAccess: Bool {
        remindersAuthStatus == .fullAccess
    }

    var hasCalendarAccess: Bool {
        calendarAuthStatus == .fullAccess
    }

    // MARK: - Create Reminder

    @discardableResult
    func createReminder(from item: BriefItem) async throws -> String {
        guard hasRemindersAccess else {
            throw EventKitError.permissionDenied("Reminders")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = item.title
        reminder.notes = item.content
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let dueDate = item.dueDate {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = components
            // Also set an alarm for the due date
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }

        if let priority = item.priority {
            reminder.priority = priority.eventKitPriority
        }

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    // MARK: - Create Calendar Event

    @discardableResult
    func createCalendarEvent(from item: BriefItem) async throws -> String {
        guard hasCalendarAccess else {
            throw EventKitError.permissionDenied("Calendar")
        }

        let event = EKEvent(eventStore: store)
        event.title = item.title
        event.notes = item.content
        event.calendar = store.defaultCalendarForNewEvents()

        if let start = item.startDate, let end = item.endDate {
            event.startDate = start
            event.endDate = end
        } else if let start = item.startDate {
            event.startDate = start
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        } else if let due = item.dueDate {
            event.startDate = due
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: due) ?? due
        } else {
            let now = Date()
            event.startDate = now
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        }

        if let location = item.location {
            let structuredLocation = EKStructuredLocation(title: location)
            event.structuredLocation = structuredLocation
        }

        // Add a 15-minute alarm
        event.addAlarm(EKAlarm(relativeOffset: -15 * 60))

        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    // MARK: - Complete Reminder

    func completeReminder(identifier: String) async throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.itemNotFound
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    // MARK: - Delete

    func deleteReminder(identifier: String) async throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw EventKitError.itemNotFound
        }
        try store.remove(reminder, commit: true)
    }

    func deleteEvent(identifier: String) async throws {
        guard let event = store.event(withIdentifier: identifier) else {
            throw EventKitError.itemNotFound
        }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: - Fetch upcoming reminders

    func fetchUpcomingReminders(limit: Int = 10) async throws -> [EKReminder] {
        guard hasRemindersAccess else { return [] }

        return try await withCheckedThrowingContinuation { cont in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                calendars: nil
            )
            store.fetchReminders(matching: predicate) { reminders in
                let sorted = (reminders ?? [])
                    .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                cont.resume(returning: Array(sorted.prefix(limit)))
            }
        }
    }
}

// MARK: - Errors

enum EventKitError: LocalizedError {
    case permissionDenied(String)
    case itemNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let app):
            return "\(app) access is required. Please enable in Settings → Privacy → \(app)."
        case .itemNotFound:
            return "The item could not be found. It may have been deleted."
        case .saveFailed(let msg):
            return "Failed to save: \(msg)"
        }
    }
}
