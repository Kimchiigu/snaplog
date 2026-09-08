//
//  KeychainStore.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import Security

/// Abstraction over the Keychain so state objects and tests don't touch it directly.
protocol KeychainStoring: Sendable {
    func saveToken(_ token: String)
    func readToken() -> String?
    func deleteToken()
}

/// Stores the backend JWT in the iOS Keychain.
struct KeychainStore: KeychainStoring {

    private let service: String

    init(service: String = "com.christopherhardygunawan.SnapLog.auth") {
        self.service = service
    }

    func saveToken(_ token: String) {
        let data = Data(token.utf8)
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "jwt"
        ]
    }
}
