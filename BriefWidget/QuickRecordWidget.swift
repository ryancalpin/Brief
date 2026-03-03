// QuickRecordWidget.swift
// One-tap widget to open Brief in recording mode, plus a stats widget

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Quick Record Widget

struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry {
        QuickRecordEntry(date: Date(), itemCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        guard let data = defaults.data(forKey: AppGroupKey.recentItems) else {
            completion(QuickRecordEntry(date: Date(), itemCount: 0))
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = (try? decoder.decode([SharedBriefItem].self, from: data)) ?? []
        completion(QuickRecordEntry(date: Date(), itemCount: items.count))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        getSnapshot(in: context) { entry in
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct QuickRecordEntry: TimelineEntry {
    let date: Date
    let itemCount: Int
}

struct QuickRecordWidget: Widget {
    let kind = "QuickRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { entry in
            QuickRecordWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Record")
        .description("Tap to instantly start recording in Brief.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct QuickRecordWidgetView: View {
    let entry: QuickRecordEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            Link(destination: URL(string: "brief://record")!) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.purple)
                    }
                    Text("Record")
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                    Text("\(entry.itemCount) items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .accessoryCircular:
            Button(intent: RecordBriefIntent()) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "mic.fill")
                        .font(.title3)
                }
            }

        case .accessoryRectangular:
            Button(intent: RecordBriefIntent()) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.purple)
                    Text("Record to Brief")
                        .font(.caption.bold())
                }
            }

        default:
            Link(destination: URL(string: "brief://record")!) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.purple)
            }
        }
    }
}

// MARK: - Stats Widget

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), todayCount: 3, totalCount: 27, completedCount: 12)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> StatsEntry {
        let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        guard let data = defaults.data(forKey: AppGroupKey.recentItems) else {
            return StatsEntry(date: Date(), todayCount: 0, totalCount: 0, completedCount: 0)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = (try? decoder.decode([SharedBriefItem].self, from: data)) ?? []
        let today = items.filter { Calendar.current.isDateInToday($0.createdAt) }
        let completed = items.filter { $0.isCompleted }
        return StatsEntry(date: Date(), todayCount: today.count,
                          totalCount: items.count, completedCount: completed.count)
    }
}

struct StatsEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let totalCount: Int
    let completedCount: Int
}

struct StatsWidget: Widget {
    let kind = "StatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            StatsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Brief Stats")
        .description("See your Brief activity at a glance.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct StatsWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            HStack(spacing: 12) {
                Label("\(entry.todayCount)", systemImage: "sun.max.fill")
                    .font(.caption2)
                Label("\(entry.completedCount)", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
            }
        } else {
            VStack(spacing: 8) {
                Label("Brief", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)

                Divider()

                HStack(spacing: 12) {
                    VStack {
                        Text("\(entry.todayCount)")
                            .font(.title2.bold())
                            .foregroundStyle(.orange)
                        Text("Today")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("\(entry.completedCount)")
                            .font(.title2.bold())
                            .foregroundStyle(.green)
                        Text("Done")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .widgetURL(URL(string: "brief://home"))
        }
    }
}
