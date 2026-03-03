// HomeViewModel.swift
// Manages the main list view — filtering, searching, sorting, and deletion

import Foundation
import SwiftData
import Observation

enum SortOrder: String, CaseIterable {
    case newestFirst = "newestFirst"
    case oldestFirst = "oldestFirst"
    case byType      = "byType"
    case byDueDate   = "byDueDate"

    var displayName: String {
        switch self {
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        case .byType:      return "By Type"
        case .byDueDate:   return "By Due Date"
        }
    }
}

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - Filter / Search state

    var searchText: String = ""
    var selectedType: BriefItemType? = nil
    var selectedDestination: BriefDestination? = nil
    var showCompleted: Bool = false
    var sortOrder: SortOrder = .newestFirst

    // MARK: - Filter predicate for SwiftData @Query

    var sortDescriptor: SortDescriptor<BriefItem> {
        switch sortOrder {
        case .newestFirst: return SortDescriptor(\.createdAt, order: .reverse)
        case .oldestFirst: return SortDescriptor(\.createdAt)
        case .byType:      return SortDescriptor(\.itemTypeRaw)
        case .byDueDate:   return SortDescriptor(\.dueDate, order: .forward)
        }
    }

    // MARK: - Client-side filtering (applied after SwiftData fetch)

    func filter(_ items: [BriefItem]) -> [BriefItem] {
        items.filter { item in
            // Completion filter
            if !showCompleted && item.isCompleted { return false }

            // Type filter
            if let type = selectedType, item.itemType != type { return false }

            // Destination filter
            if let dest = selectedDestination, item.destination != dest { return false }

            // Search text
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let matchesTitle = item.title.lowercased().contains(query)
                let matchesContent = item.content?.lowercased().contains(query) ?? false
                let matchesTags = item.tags.contains { $0.lowercased().contains(query) }
                if !matchesTitle && !matchesContent && !matchesTags { return false }
            }

            return true
        }
    }

    // MARK: - Stats

    func stats(from items: [BriefItem]) -> HomeStats {
        HomeStats(
            total: items.count,
            completed: items.filter { $0.isCompleted }.count,
            todayCount: items.filter {
                Calendar.current.isDateInToday($0.createdAt)
            }.count,
            reminderCount: items.filter { $0.itemType == .reminder }.count,
            noteCount: items.filter { $0.itemType == .note }.count
        )
    }

    // MARK: - Group by date

    func grouped(_ items: [BriefItem]) -> [(String, [BriefItem])] {
        let filtered = filter(items)
        let calendar = Calendar.current
        var groups: [(String, [BriefItem])] = []
        var dict: [String: [BriefItem]] = [:]

        for item in filtered {
            let key: String
            if calendar.isDateInToday(item.createdAt) {
                key = "Today"
            } else if calendar.isDateInYesterday(item.createdAt) {
                key = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                key = formatter.string(from: item.createdAt)
            }
            dict[key, default: []].append(item)
        }

        // Sort groups: Today first, Yesterday second, then dates descending
        let orderedKeys = dict.keys.sorted { a, b in
            if a == "Today" { return true }
            if b == "Today" { return false }
            if a == "Yesterday" { return true }
            if b == "Yesterday" { return false }
            return a > b
        }

        for key in orderedKeys {
            groups.append((key, dict[key] ?? []))
        }
        return groups
    }
}

struct HomeStats {
    let total: Int
    let completed: Int
    let todayCount: Int
    let reminderCount: Int
    let noteCount: Int

    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
