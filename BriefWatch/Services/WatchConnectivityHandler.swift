// WatchConnectivityHandler.swift
// WatchConnectivity delegate for the watchOS side

import Foundation
import WatchConnectivity

final class WatchConnectivityHandler: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchConnectivityHandler()

    @Published var isReachable = false
    @Published var recentItems: [SharedBriefItem] = []
    @Published var lastProcessingResult: SharedBriefItem?
    @Published var processingAck: Bool = false    // iPhone confirmed processing

    private let session = WCSession.default
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send transcript to iPhone

    func sendTranscript(_ transcript: String) {
        guard session.activationState == .activated else { return }
        let message: [String: Any] = [
            "type": "transcriptReady",
            "transcript": transcript
        ]
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                DispatchQueue.main.async {
                    self?.processingAck = true
                }
            }, errorHandler: { [weak self] error in
                // Fallback: store in App Group for background pick-up
                self?.storeTranscriptInAppGroup(transcript)
            })
        } else {
            // Phone not reachable, store for later
            storeTranscriptInAppGroup(transcript)
            session.transferUserInfo(message)
        }
    }

    private func storeTranscriptInAppGroup(_ transcript: String) {
        AppGroup.defaults.set(transcript, forKey: AppGroupKey.pendingTranscript)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.loadContextIfAvailable()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.parseContext(applicationContext)
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.handleMessage(message)
            replyHandler(["status": "received"])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handleMessage(message)
        }
    }

    func session(_ session: WCSession,
                 didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            self.parseContext(userInfo)
        }
    }

    // MARK: - Message handlers

    private func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "processingResult":
            if let itemDict = message["item"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: itemDict),
               let item = try? decoder.decode(SharedBriefItem.self, from: data) {
                lastProcessingResult = item
                recentItems.insert(item, at: 0)
            }
        case "recordingAck":
            processingAck = message["success"] as? Bool ?? false
        default:
            break
        }
    }

    private func parseContext(_ context: [String: Any]) {
        guard let itemsArray = context["recentItems"] as? [[String: Any]],
              let data = try? JSONSerialization.data(withJSONObject: itemsArray),
              let items = try? decoder.decode([SharedBriefItem].self, from: data) else { return }
        recentItems = items
    }

    private func loadContextIfAvailable() {
        let context = session.receivedApplicationContext
        if !context.isEmpty { parseContext(context) }
    }
}
