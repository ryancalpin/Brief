// RecordBriefIntent.swift
// AppIntents for Action Button, Siri Shortcuts, and Control Center

import AppIntents
import Foundation

// MARK: - Record Intent (Action Button / Siri / Shortcuts)

struct RecordBriefIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Voice Note"
    static var description = IntentDescription(
        "Open Brief and start recording a voice note, reminder, or calendar event.",
        categoryName: "Brief"
    )
    static var openAppWhenRun = true

    // This is what gets triggered when the Action Button is pressed
    static var isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        // The app will receive this notification and open in recording mode
        NotificationCenter.default.post(name: .briefStartRecording, object: nil)
        return .result()
    }
}

// MARK: - Quick Add Intent (with Siri parameter)

struct QuickAddBriefIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Brief"
    static var description = IntentDescription(
        "Quickly add a note, reminder, or calendar event to Brief using your voice.",
        categoryName: "Brief"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Content", description: "What would you like to add?")
    var content: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let content, !content.isEmpty {
            // Store for the app to pick up when it foregrounds
            SharedDefaults.shared.pendingTranscript = content
            return .result(dialog: "Got it! I'll add '\(content)' to Brief.")
        } else {
            return .result(dialog: "Please provide content to add to Brief.")
        }
    }
}

// MARK: - Create Reminder Intent (Siri-integrated)

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Reminder in Brief"
    static var description = IntentDescription(
        "Create a reminder that Brief will sync to Apple Reminders.",
        categoryName: "Brief"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Reminder", description: "What do you want to be reminded about?")
    var reminder: String

    @Parameter(title: "Due Date", description: "When should this reminder be due?")
    var dueDate: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let transcript = dueDate != nil
            ? "Remind me to \(reminder) on \(dueDate!.formatted(date: .abbreviated, time: .shortened))"
            : "Remind me to \(reminder)"
        SharedDefaults.shared.pendingTranscript = transcript
        return .result(dialog: "I'll remind you to \(reminder).")
    }
}

// MARK: - View Recent Items Intent

struct ViewBriefItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "View Recent Brief Items"
    static var description = IntentDescription(
        "Open Brief to view your recent notes, reminders, and calendar events.",
        categoryName: "Brief"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let briefStartRecording = Notification.Name("com.brief.startRecording")
    static let briefProcessPendingTranscript = Notification.Name("com.brief.processPending")
}
