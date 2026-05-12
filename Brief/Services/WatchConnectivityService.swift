// WatchConnectivityService.swift
// Handles iPhone ↔ Apple Watch communication via WatchConnectivity

import Foundation
import WatchConnectivity
import Observation

@Observable
@MainActor
final class WatchConnectivityService: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchConnectivityService()

    var isPaired = false
    var isWatchAppInstalled = false
    var isReachable = false

    // Pending transcript received from Watch
    var pendingWatchTranscript: String?
    var watchRequestedProcessing = false

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    // MARK: - Setup

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send to Watch

    /// Pushes recent items to the Watch app's complication data and context.
    func syncRecentItems(_ items: [SharedBriefItem]) {
        guard let session, session.activationState == .activated else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(Array(items.prefix(10))),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return }

        let context: [String: Any] = [
            "recentItems": json,
            "lastSync": ISO8601DateFormatter().string(from: Date())
        ]

        // Update application context (latest snapshot, survives app restarts)
        try? session.updateApplicationContext(context)

        // Also update complication data if Watch is reachable
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(context)
        }
    }

    /// Sends processing result back to Watch after processing its transcript.
    func sendProcessingResult(_ item: SharedBriefItem) {
        guard let session, session.isReachable else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(item),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        session.sendMessage(
            ["type": "processingResult", "item": dict],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    /// Sends a recording confirmation to the Watch (to dismiss recording UI).
    func sendRecordingAck(success: Bool, message: String? = nil) {
        guard let session, session.isReachable else { return }
        var payload: [String: Any] = ["type": "recordingAck", "success": success]
        if let message { payload["message"] = message }
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                              activationDidCompleteWith activationState: WCSessionActivationState,
                              error: Error?) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    /// Receives messages from Watch
    nonisolated func session(_ session: WCSession,
                              didReceiveMessage message: [String: Any],
                              replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handleWatchMessage(message, replyHandler: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleWatchMessage(message, replyHandler: nil)
        }
    }

    // MARK: - Message handling

    private func handleWatchMessage(_ message: [String: Any],
                                    replyHandler: (([String: Any]) -> Void)?) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "transcriptReady":
            // Watch recorded audio and got a transcript; iPhone should process it
            if let transcript = message["transcript"] as? String {
                pendingWatchTranscript = transcript
                watchRequestedProcessing = true
                SharedDefaults.shared.pendingTranscript = transcript
                replyHandler?(["status": "received"])
            }

        case "ping":
            replyHandler?(["status": "alive", "time": ISO8601DateFormatter().string(from: Date())])

        default:
            break
        }
    }
}
