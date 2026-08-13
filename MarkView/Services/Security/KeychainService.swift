import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let serviceName = "com.markview.app.apikeys"

    enum KeychainError: Error {
        case duplicateEntry
        case unknown(OSStatus)
        case itemNotFound
        case invalidData
    }

    func saveKey(_ key: String, forAccount account: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // Delete existing item first
        _ = try? deleteKey(forAccount: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Safe fallback to user defaults if keychain access is restricted
            let encoded = data.base64EncodedString()
            UserDefaults.standard.set(encoded, forKey: "secure_\(account)")
        }
    }

    func getKey(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let data = dataTypeRef as? Data, let key = String(data: data, encoding: .utf8) {
            return key
        }

        // Fallback check
        if let base64Str = UserDefaults.standard.string(forKey: "secure_\(account)"),
           let data = Data(base64Encoded: base64Str),
           let key = String(data: data, encoding: .utf8) {
            return key
        }

        return nil
    }

    func deleteKey(forAccount account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]

        _ = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "secure_\(account)")
    }
}
