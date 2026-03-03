// NotesExportService.swift
// Exports notes to Apple Notes via URL schemes and share sheet

import Foundation
import UIKit

/// Exports content to Apple Notes using URL schemes.
/// For programmatic note creation, we open Apple Notes with pre-filled content.
/// Full write access to Notes.app is not available via public API on iOS.
final class NotesExportService {

    // MARK: - Open Notes app with content

    /// Deep-links into Apple Notes with a search query or creates a new note.
    @MainActor
    func openNotes() {
        // Opens Apple Notes app
        if let url = URL(string: "mobilenotes://") {
            UIApplication.shared.open(url)
        }
    }

    /// Attempts to open Notes in "new note" mode (not officially documented,
    /// may vary by iOS version).
    @MainActor
    func openNewNote(withTitle title: String, body: String) {
        // Encode the note content as a URL parameter
        let content = body.isEmpty ? title : "\(title)\n\n\(body)"
        if let encoded = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "mobilenotes://new?content=\(encoded)") {
            UIApplication.shared.open(url) { success in
                if !success {
                    // Fallback: just open Notes
                    if let fallback = URL(string: "mobilenotes://") {
                        UIApplication.shared.open(fallback)
                    }
                }
            }
        }
    }

    // MARK: - Share sheet (most reliable cross-version approach)

    /// Presents a share sheet from the given view controller, pre-configured for Apple Notes.
    @MainActor
    func shareToNotes(title: String, body: String, from viewController: UIViewController) {
        let content = body.isEmpty ? title : "\(title)\n\n\(body)"
        let activityVC = UIActivityViewController(
            activityItems: [content],
            applicationActivities: nil
        )
        // Exclude irrelevant share options
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .print
        ]
        viewController.present(activityVC, animated: true)
    }

    // MARK: - Check Notes availability

    var isNotesAppInstalled: Bool {
        URL(string: "mobilenotes://").map { UIApplication.shared.canOpenURL($0) } ?? false
    }

    // MARK: - Format note content

    func formatNoteContent(from item: BriefItem) -> String {
        var lines: [String] = [item.title]

        if let content = item.content, !content.isEmpty {
            lines.append("")
            lines.append(content)
        }

        if !item.tags.isEmpty {
            lines.append("")
            lines.append("Tags: " + item.tags.joined(separator: ", "))
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append("")
        lines.append("Created via Brief on \(formatter.string(from: item.createdAt))")

        return lines.joined(separator: "\n")
    }
}
