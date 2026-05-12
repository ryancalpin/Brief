// APIGatewayService.swift
// Single routing point for all AI API calls — App Store mode vs BYOK mode.
//
// App Store mode: routes through a managed API gateway (JWT auth).
// BYOK mode: routes directly to OpenRouter with user's own API key.
//
// If the gateway is configured but unreachable, auto-falls-back to BYOK.
// This prevents App Store builds from breaking if the gateway is down.

import Foundation

enum APIGatewayError: LocalizedError {
    case notConfigured
    case missingCredential
    case gatewayUnreachable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No AI service configured. Add an OpenRouter key in Settings."
        case .missingCredential:
            return "Authentication credential missing. Please sign in again."
        case .gatewayUnreachable:
            return "API gateway is currently unreachable. Using your OpenRouter key instead."
        }
    }
}

final class APIGatewayService: Sendable {

    static let shared = APIGatewayService()

    // MARK: - Gateway URL (from build configuration)

    /// Read from Info.plist at launch. Set via Config.xcconfig or project.yml.
    /// Empty string = BYOK mode. Non-empty = App Store gateway mode.
    private static let gatewayURL: String = {
        Bundle.main.object(forInfoDictionaryKey: "API_GATEWAY_URL") as? String ?? ""
    }()

    /// True when a gateway URL is configured in the build settings.
    /// Does NOT guarantee the gateway is reachable — see `gatewayReachable`.
    static var isAppStoreMode: Bool { !gatewayURL.isEmpty }

    // MARK: - Gateway health

    /// Cached reachability status. Checked once on first request, then cached.
    /// Thread-safe via actor isolation (this class is Sendable).
    private var _gatewayReachable: Bool?
    private var _healthCheckInProgress = false
    private let healthCheckLock = NSLock()

    /// Whether the configured gateway is reachable.
    /// - `nil` = not yet checked
    /// - `true` = gateway is healthy
    /// - `false` = gateway unreachable, falling back to BYOK
    var gatewayReachable: Bool? {
        healthCheckLock.lock()
        defer { healthCheckLock.unlock() }
        return _gatewayReachable
    }

    /// The effective mode: are we actually using the gateway right now?
    var isUsingGateway: Bool {
        Self.isAppStoreMode && gatewayReachable == true
    }

    private init() {}

    // MARK: - Request config

    /// Returns the base URL and auth headers for AI requests.
    ///
    /// Priority:
    /// 1. Gateway (if configured AND reachable) — JWT auth
    /// 2. BYOK (user's OpenRouter key) — API key auth
    func requestConfig() throws -> (baseURL: String, headers: [String: String]) {
        if Self.isAppStoreMode {
            // Check gateway health on first call
            if gatewayReachable == nil {
                Task { await checkGatewayHealth() }
                // On first call before health check completes: try gateway,
                // fall back to BYOK if it fails at request time
            }

            if gatewayReachable == true {
                guard let jwt = KeychainService.shared.read(key: .gatewayJWT), !jwt.isEmpty else {
                    throw APIGatewayError.missingCredential
                }
                return (
                    baseURL: Self.gatewayURL,
                    headers: [
                        "Authorization": "Bearer \(jwt)",
                        "Content-Type": "application/json"
                    ]
                )
            }

            // Gateway not reachable — fall through to BYOK
        }

        // BYOK mode (or gateway fallback)
        guard let key = KeychainService.shared.read(key: .openRouterKey), !key.isEmpty else {
            throw APIGatewayError.notConfigured
        }
        return (
            baseURL: "https://openrouter.ai/api/v1",
            headers: [
                "Authorization": "Bearer \(key)",
                "Content-Type": "application/json",
                "HTTP-Referer": "com.brief.app",
                "X-Title": "Brief"
            ]
        )
    }

    // MARK: - Health check

    /// Pings the gateway's /health endpoint (with 3s timeout).
    /// Caches the result so subsequent calls are instant.
    func checkGatewayHealth() async {
        guard Self.isAppStoreMode else { return }

        healthCheckLock.lock()
        if _gatewayReachable != nil || _healthCheckInProgress {
            healthCheckLock.unlock()
            return
        }
        _healthCheckInProgress = true
        healthCheckLock.unlock()

        let reachable = await pingGateway()

        healthCheckLock.lock()
        _gatewayReachable = reachable
        _healthCheckInProgress = false
        healthCheckLock.unlock()
    }

    /// Force a re-check (e.g., after network change).
    func resetHealthCheck() {
        healthCheckLock.lock()
        _gatewayReachable = nil
        _healthCheckInProgress = false
        healthCheckLock.unlock()
    }

    private func pingGateway() async -> Bool {
        guard let url = URL(string: "\(Self.gatewayURL)/health") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
