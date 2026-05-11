// APIGatewayService.swift
// Single routing point for all AI API calls — App Store mode vs BYOK mode

import Foundation

enum APIGatewayError: LocalizedError {
    case notConfigured
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No AI service configured. Add an OpenRouter key in Settings."
        case .missingCredential:
            return "Authentication credential missing. Please sign in again."
        }
    }
}

final class APIGatewayService: Sendable {

    static let shared = APIGatewayService()

    // Build flag set in project.yml for App Store builds only. Empty in open source builds.
    private static let gatewayURL: String = {
        Bundle.main.object(forInfoDictionaryKey: "API_GATEWAY_URL") as? String ?? ""
    }()

    static var isAppStoreMode: Bool { !gatewayURL.isEmpty }

    private init() {}

    // Returns the base URL and auth headers to use for all AI requests.
    // App Store mode: gateway URL + JWT from Keychain
    // BYOK mode: openrouter.ai + user's OpenRouter key from Keychain
    func requestConfig() throws -> (baseURL: String, headers: [String: String]) {
        if Self.isAppStoreMode {
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
        } else {
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
    }
}
