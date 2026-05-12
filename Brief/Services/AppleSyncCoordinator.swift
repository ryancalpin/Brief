// AppleSyncCoordinator.swift
// Handles EventKit completion toggling, notes export, and Watch sync side-effects

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppleSyncCoordinator: @unchecked Sendable {

    private let eventKitService: EventKitService
    private let ekSyncService = EventKitSyncService()
    private let watchService: WatchConnectivityService
    private var modelContext: ModelContext?

    init(
        eventKitService: EventKitService,
        watchService: WatchConnectivityService = .shared
    ) {
        self.eventKitService = eventKitService
        self.watchService = watchService
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Toggle completion

    func toggleComplete(_ item: BriefItem) {
        item.isCompleted.toggle()
        applyCompletionSideEffects(item)
    }

    /// Call this when a Toggle binding has already mutated isCompleted —
    /// skips the toggle and only runs side effects.
    func applyCompletionSideEffects(_ item: BriefItem) {
        item.updatedAt = Date()
        if item.isCompleted { item.completedAt = Date() }
        else                { item.completedAt = nil }

        if item.ekIdentifier != nil, item.ekSyncEnabled {
            Task { try? await ekSyncService.complete(item) }
        } else if let id = item.externalIdentifier, item.destination == .reminders {
            Task { try? await eventKitService.completeReminder(identifier: id) }
        }

        try? modelContext?.save()
        SharedDefaults.shared.updateItem(item.toShared())

        // Push updated state to Watch
        watchService.syncRecentItems(SharedDefaults.shared.recentItems)
    }

    // MARK: - Delete (cleans up EventKit mirror)

    func deleteMirroredItem(_ item: BriefItem) {
        if item.ekSyncEnabled, let _ = item.ekIdentifier {
            Task { try? await ekSyncService.delete(item) }
        }
    }
}
