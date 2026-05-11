// WatchLocalBuffer.swift
// Buffers voice transcripts when iPhone is unreachable.
// Drains automatically when WCSession.isReachable becomes true.

import Foundation
import WatchConnectivity

final class WatchLocalBuffer: ObservableObject {

    static let shared = WatchLocalBuffer()

    @Published private(set) var pendingCount: Int = 0

    private struct BufferedItem: Codable {
        let transcript: String
        let recordedAt: Date
    }

    private var items: [BufferedItem] = []
    private let defaultsKey = "com.brief.watch.pendingBuffer"
    private let defaults = AppGroup.defaults

    private init() {
        load()
    }

    // MARK: - Public API

    // Add a transcript to the buffer when iPhone is unreachable.
    func enqueue(transcript: String, recordedAt: Date = Date()) {
        items.append(BufferedItem(transcript: transcript, recordedAt: recordedAt))
        persist()
        updateCount()
    }

    // Drain all buffered items to iPhone via WatchConnectivity.
    // Call when WCSession.isReachable transitions to true.
    func drain(session: WCSession) {
        guard !items.isEmpty, session.activationState == .activated else { return }
        let toSend = items
        items.removeAll()
        persist()
        updateCount()

        for buffered in toSend {
            let message: [String: Any] = [
                "type": "transcriptReady",
                "transcript": buffered.transcript,
                "recordedAt": ISO8601DateFormatter().string(from: buffered.recordedAt)
            ]
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil, errorHandler: { [weak self] _ in
                    // Re-enqueue on send failure
                    self?.enqueue(transcript: buffered.transcript, recordedAt: buffered.recordedAt)
                })
            } else {
                session.transferUserInfo(message)
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: defaultsKey)
        defaults.set(items.count, forKey: "com.brief.watch.pendingCount")
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([BufferedItem].self, from: data) else { return }
        items = decoded
        updateCount()
    }

    private func updateCount() {
        pendingCount = items.count
        defaults.set(items.count, forKey: "com.brief.watch.pendingCount")
    }
}
