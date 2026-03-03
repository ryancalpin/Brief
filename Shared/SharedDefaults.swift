// SharedDefaults.swift
// Typed wrapper around App Group UserDefaults for cross-target access

import Foundation

@MainActor
final class SharedDefaults {
    static let shared = SharedDefaults()
    private let defaults = AppGroup.defaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Recent Items

    var recentItems: [SharedBriefItem] {
        get {
            guard let data = defaults.data(forKey: AppGroupKey.recentItems),
                  let items = try? decoder.decode([SharedBriefItem].self, from: data) else {
                return []
            }
            return items
        }
        set {
            // Keep only the most recent 50 items for widget/Watch performance
            let trimmed = Array(newValue.sorted { $0.createdAt > $1.createdAt }.prefix(50))
            if let data = try? encoder.encode(trimmed) {
                defaults.set(data, forKey: AppGroupKey.recentItems)
                defaults.set(Date(), forKey: AppGroupKey.lastUpdated)
            }
        }
    }

    func addItem(_ item: SharedBriefItem) {
        var items = recentItems
        items.insert(item, at: 0)
        recentItems = items
    }

    func updateItem(_ item: SharedBriefItem) {
        var items = recentItems
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
            recentItems = items
        }
    }

    var lastUpdated: Date? {
        defaults.object(forKey: AppGroupKey.lastUpdated) as? Date
    }

    // MARK: - Recording State

    var isRecording: Bool {
        get { defaults.bool(forKey: AppGroupKey.recordingState) }
        set { defaults.set(newValue, forKey: AppGroupKey.recordingState) }
    }

    // MARK: - AI Provider

    var aiProviderRaw: String? {
        get { defaults.string(forKey: AppGroupKey.aiProvider) }
        set { defaults.set(newValue, forKey: AppGroupKey.aiProvider) }
    }

    // MARK: - Watch Handoff

    var pendingTranscript: String? {
        get { defaults.string(forKey: AppGroupKey.pendingTranscript) }
        set { defaults.set(newValue, forKey: AppGroupKey.pendingTranscript) }
    }

    var watchLastSync: Date? {
        get { defaults.object(forKey: AppGroupKey.watchLastSync) as? Date }
        set { defaults.set(newValue, forKey: AppGroupKey.watchLastSync) }
    }
}
