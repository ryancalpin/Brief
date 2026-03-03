// BriefShortcutsProvider.swift
// Exposes Brief actions to Siri Shortcuts and the Shortcuts app

import AppIntents

struct BriefShortcutsProvider: AppShortcutsProvider {

    /// The color tint used in Shortcuts app
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordBriefIntent(),
            phrases: [
                "Open \(.applicationName) to record",
                "Record a note in \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Add a reminder in \(.applicationName)"
            ],
            shortTitle: "Record Voice Note",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: QuickAddBriefIntent(),
            phrases: [
                "Add \(\.$content) to \(.applicationName)",
                "Tell \(.applicationName) \(\.$content)",
                "Note in \(.applicationName) \(\.$content)"
            ],
            shortTitle: "Add to Brief",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "Remind me \(\.$reminder) in \(.applicationName)",
                "Create a reminder for \(\.$reminder) in \(.applicationName)"
            ],
            shortTitle: "Create Reminder",
            systemImageName: "checklist"
        )

        AppShortcut(
            intent: ViewBriefItemsIntent(),
            phrases: [
                "Show my \(.applicationName) notes",
                "Open \(.applicationName) items",
                "What's in \(.applicationName)"
            ],
            shortTitle: "View Items",
            systemImageName: "list.bullet"
        )
    }
}
