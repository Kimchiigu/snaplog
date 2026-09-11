import Foundation
import Security

protocol KeychainStoring: Sendable {
    func saveToken(_ token: String)
    func readToken() -> String?
    func deleteToken()
    func saveAppleUserId(_ appleUserId: String?)
    func readAppleUserId() -> String?
}

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

    func saveAppleUserId(_ appleUserId: String?) {
        let query = baseQuery(account: "appleUserId")
        SecItemDelete(query as CFDictionary)
        guard let appleUserId, !appleUserId.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(appleUserId.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func readAppleUserId() -> String? {
        var query = baseQuery(account: "appleUserId")
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func baseQuery(account: String = "jwt") -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
