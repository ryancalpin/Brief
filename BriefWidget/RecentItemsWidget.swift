// RecentItemsWidget.swift
// WidgetKit widget showing recent Brief items

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct RecentItemsProvider: TimelineProvider {

    func placeholder(in context: Context) -> RecentItemsEntry {
        RecentItemsEntry(date: Date(), items: RecentItemsEntry.placeholderItems)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentItemsEntry) -> Void) {
        let entry = RecentItemsEntry(date: Date(), items: loadItems())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentItemsEntry>) -> Void) {
        let entry = RecentItemsEntry(date: Date(), items: loadItems())
        // Refresh every 15 minutes or when the app updates the App Group
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadItems() -> [SharedBriefItem] {
        let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        guard let data = defaults.data(forKey: AppGroupKey.recentItems) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SharedBriefItem].self, from: data)) ?? []
    }
}

struct RecentItemsEntry: TimelineEntry {
    let date: Date
    let items: [SharedBriefItem]

    static let placeholderItems: [SharedBriefItem] = [
        SharedBriefItem(id: UUID(), title: "Buy groceries", content: nil,
                        itemTypeRaw: "reminder", destinationRaw: "reminders",
                        createdAt: Date(), isCompleted: false, dueDate: nil, tags: []),
        SharedBriefItem(id: UUID(), title: "Team meeting notes", content: nil,
                        itemTypeRaw: "note", destinationRaw: "notes",
                        createdAt: Date().addingTimeInterval(-3600), isCompleted: false, dueDate: nil, tags: []),
        SharedBriefItem(id: UUID(), title: "Doctor appointment", content: nil,
                        itemTypeRaw: "calendarEvent", destinationRaw: "calendar",
                        createdAt: Date().addingTimeInterval(-7200), isCompleted: false,
                        dueDate: Date().addingTimeInterval(86400), tags: [])
    ]
}

// MARK: - Widget

struct RecentItemsWidget: Widget {
    let kind: String = "RecentItemsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentItemsProvider()) { entry in
            RecentItemsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Items")
        .description("See your most recent Brief notes and reminders.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Widget Views

struct RecentItemsWidgetView: View {
    let entry: RecentItemsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:   SmallRecentView(entry: entry)
        case .systemMedium:  MediumRecentView(entry: entry)
        case .systemLarge:   LargeRecentView(entry: entry)
        case .accessoryRectangular: AccessoryRecentView(entry: entry)
        default:             SmallRecentView(entry: entry)
        }
    }
}

struct SmallRecentView: View {
    let entry: RecentItemsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "mic.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text("Brief")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                Spacer()
            }

            if let first = entry.items.first {
                VStack(alignment: .leading, spacing: 3) {
                    Label {
                        Text(first.title)
                            .font(.caption.bold())
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: first.itemType.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No items yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.date.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .widgetURL(URL(string: "brief://home"))
    }
}

struct MediumRecentView: View {
    let entry: RecentItemsEntry

    private var displayItems: [SharedBriefItem] { Array(entry.items.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Brief", systemImage: "mic.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                Spacer()
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            if displayItems.isEmpty {
                Text("Tap the mic button to add your first item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayItems) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.itemType.systemImage)
                            .font(.caption)
                            .foregroundStyle(.purple)
                            .frame(width: 16)
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                            .strikethrough(item.isCompleted)
                        Spacer()
                        if let due = item.dueDate, !item.isCompleted {
                            Text(due.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundStyle(due < Date() ? .red : .secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .widgetURL(URL(string: "brief://home"))
    }
}

struct LargeRecentView: View {
    let entry: RecentItemsEntry

    private var displayItems: [SharedBriefItem] { Array(entry.items.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Brief", systemImage: "mic.fill")
                    .font(.headline.bold())
                    .foregroundStyle(.purple)
                Spacer()
                Link(destination: URL(string: "brief://record")!) {
                    Image(systemName: "mic.badge.plus")
                        .foregroundStyle(.purple)
                }
            }

            Divider()

            if displayItems.isEmpty {
                Spacer()
                ContentUnavailableView("No Items", systemImage: "mic.fill")
                Spacer()
            } else {
                ForEach(displayItems) { item in
                    Link(destination: URL(string: "brief://item/\(item.id)")!) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(typeColor(item.itemType).opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: item.itemType.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(typeColor(item.itemType))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                Text(item.destination.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let due = item.dueDate, !item.isCompleted {
                                Text(due.formatted(.relative(presentation: .named)))
                                    .font(.caption2)
                                    .foregroundStyle(due < Date() ? .red : .secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if item.id != displayItems.last?.id {
                        Divider()
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private func typeColor(_ type: SharedBriefItem.SharedItemType) -> Color {
        switch type {
        case .reminder:      return .blue
        case .note:          return .yellow
        case .calendarEvent: return .red
        case .list:          return .green
        case .generic:       return .purple
        }
    }
}

struct AccessoryRecentView: View {
    let entry: RecentItemsEntry

    var body: some View {
        if let item = entry.items.first {
            HStack(spacing: 4) {
                Image(systemName: item.itemType.systemImage)
                    .font(.caption2)
                Text(item.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
        } else {
            Label("Brief", systemImage: "mic.fill")
                .font(.caption2)
        }
    }
}
