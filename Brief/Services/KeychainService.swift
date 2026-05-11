// KeychainService.swift
// Minimal Security-framework Keychain wrapper

import Foundation
import Security

enum KeychainKey: String {
    case openRouterKey = "com.brief.app.openRouterKey"
    case gatewayJWT    = "com.brief.app.gatewayJWT"
    case openAIKey     = "com.brief.app.openAIKey"      // legacy – migration only
    case anthropicKey  = "com.brief.app.anthropicKey"   // legacy – migration only
}

final class KeychainService: Sendable {

    static let shared = KeychainService()
    private init() {}

    // MARK: - Write

    @discardableResult
    func write(key: KeychainKey, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read

    func read(key: KeychainKey) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key.rawValue,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    // MARK: - Delete

    @discardableResult
    func delete(key: KeychainKey) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
