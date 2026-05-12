// EventKitSyncService.swift
// Mirrors BriefItems to Apple Reminders (v1). Calendar sync is v1.1.

import Foundation
import EventKit
import SwiftData

@Observable
@MainActor
final class EventKitSyncService: @unchecked Sendable {

    private let store = EKEventStore()

    // MARK: - Mirror to Apple Reminders

    // Mirror a .reminder BriefItem to Apple Reminders.
    // Sets item.ekIdentifier on success.
    // Only call when user has enabled Reminders sync AND item.itemType == .reminder.
    func mirror(_ item: BriefItem, context: ModelContext) async throws {
        guard item.ekSyncEnabled,
              item.itemType == .reminder || item.itemType == .list else { return }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else {
            do {
                let granted = try await store.requestFullAccessToReminders()
                guard granted else {
                    item.syncError = "Reminders access denied."
                    return
                }
            } catch {
                item.syncError = error.localizedDescription
                return
            }
        }

        do {
            // Reuse existing EKReminder if we've already synced this item;
            // create a new one otherwise. Prevents duplicate reminders on re-sync.
            let reminder: EKReminder
            if let id = item.ekIdentifier,
               let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
                reminder = existing
                reminder.alarms?.forEach { reminder.removeAlarm($0) }
            } else {
                reminder = EKReminder(eventStore: store)
                reminder.calendar = store.defaultCalendarForNewReminders()
            }
            reminder.title = item.title
            reminder.notes = item.content
            reminder.isCompleted = item.isCompleted

            if let due = item.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: due
                )
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            } else {
                reminder.dueDateComponents = nil
            }

            if let p = item.priority {
                reminder.priority = p.eventKitPriority
            }

            try store.save(reminder, commit: true)
            item.ekIdentifier = reminder.calendarItemIdentifier
            item.syncError = nil
            try? context.save()
        } catch {
            item.syncError = error.localizedDescription
        }
    }

    // Mark complete in Apple Reminders.
    func complete(_ item: BriefItem) async throws {
        guard let id = item.ekIdentifier,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    // Pull completion state from Apple Reminders → SwiftData.
    // Call on app foreground. Match on ekIdentifier.
    func pullCompletions(context: ModelContext) async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else { return }

        let descriptor = FetchDescriptor<BriefItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        let syncedItems = items.filter { $0.ekIdentifier != nil && $0.ekSyncEnabled }

        for item in syncedItems {
            guard let id = item.ekIdentifier,
                  let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            if reminder.isCompleted && !item.isCompleted {
                item.isCompleted = true
                item.completedAt = reminder.completionDate ?? Date()
            }
        }
        try? context.save()
    }

    // Delete from Apple Reminders when item deleted in Brief.
    func delete(_ item: BriefItem) async throws {
        guard let id = item.ekIdentifier,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }

    // MARK: - Calendar sync (v1.1)
    // TODO: Implement Apple Calendar sync in v1.1
}
