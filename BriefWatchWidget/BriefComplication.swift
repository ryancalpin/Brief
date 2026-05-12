// BriefComplication.swift
// watchOS Widget/Complication using WidgetKit

import SwiftUI
import WidgetKit

// MARK: - Complication Provider

struct BriefComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> BriefComplicationEntry {
        BriefComplicationEntry(date: Date(), itemCount: 0, latestTitle: "Brief", pendingCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefComplicationEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefComplicationEntry>) -> Void) {
        let entry = makeEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> BriefComplicationEntry {
        let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let itemCount: Int
        let latestTitle: String?

        if let data = defaults.data(forKey: AppGroupKey.recentItems) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = (try? decoder.decode([SharedBriefItem].self, from: data)) ?? []
            itemCount   = items.filter { !$0.isCompleted }.count
            latestTitle = items.first?.title
        } else {
            itemCount   = 0
            latestTitle = nil
        }

        let pendingCount = defaults.integer(forKey: "com.brief.watch.pendingCount")

        return BriefComplicationEntry(
            date: Date(),
            itemCount: itemCount,
            latestTitle: latestTitle,
            pendingCount: pendingCount
        )
    }
}

struct BriefComplicationEntry: TimelineEntry {
    let date: Date
    let itemCount: Int
    let latestTitle: String?
    let pendingCount: Int
}

// MARK: - Complication Widget

struct BriefComplication: Widget {
    let kind = "BriefComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BriefComplicationProvider()) { entry in
            BriefComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Brief")
        .description("Quick access to Brief and your item count.")
        .supportedFamilies([
            .accessoryCorner,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Complication Views

struct BriefComplicationView: View {
    let entry: BriefComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .foregroundStyle(.purple)
            }
            .widgetLabel {
                if entry.pendingCount > 0 {
                    Text("\(entry.pendingCount) pending")
                } else {
                    Text("\(entry.itemCount) items")
                }
            }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.pendingCount > 0 ? "clock.badge.exclamationmark" : "mic.fill")
                        .font(.caption2)
                    Text(entry.pendingCount > 0 ? "\(entry.pendingCount)" : "\(entry.itemCount)")
                        .font(.caption2.bold().monospacedDigit())
                }
                .foregroundStyle(entry.pendingCount > 0 ? .orange : .purple)
            }

        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Brief")
                        .font(.caption2.bold())
                    if entry.pendingCount > 0 {
                        Text("\(entry.pendingCount) pending sync")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let title = entry.latestTitle {
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("\(entry.itemCount) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .accessoryInline:
            if entry.pendingCount > 0 {
                Label("\(entry.pendingCount) pending", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            } else {
                Label("\(entry.itemCount) in Brief", systemImage: "mic.fill")
                    .foregroundStyle(.purple)
            }

        default:
            Image(systemName: "mic.fill")
                .foregroundStyle(.purple)
        }
    }
}

// MARK: - Watch Widget Bundle

@main
struct BriefWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        BriefComplication()
    }
}
