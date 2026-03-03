// BriefComplication.swift
// watchOS Widget/Complication using WidgetKit

import SwiftUI
import WidgetKit

// MARK: - Complication Provider

struct BriefComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> BriefComplicationEntry {
        BriefComplicationEntry(date: Date(), itemCount: 0, latestTitle: "Brief")
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
        guard let data = defaults.data(forKey: AppGroupKey.recentItems) else {
            return BriefComplicationEntry(date: Date(), itemCount: 0, latestTitle: nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = (try? decoder.decode([SharedBriefItem].self, from: data)) ?? []
        return BriefComplicationEntry(
            date: Date(),
            itemCount: items.filter { !$0.isCompleted }.count,
            latestTitle: items.first?.title
        )
    }
}

struct BriefComplicationEntry: TimelineEntry {
    let date: Date
    let itemCount: Int
    let latestTitle: String?
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
            .widgetLabel(Text("\(entry.itemCount) items"))

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                    Text("\(entry.itemCount)")
                        .font(.caption2.bold().monospacedDigit())
                }
                .foregroundStyle(.purple)
            }

        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Brief")
                        .font(.caption2.bold())
                    if let title = entry.latestTitle {
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
            Label("\(entry.itemCount) in Brief", systemImage: "mic.fill")
                .foregroundStyle(.purple)

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
