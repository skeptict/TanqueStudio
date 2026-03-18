//
//  KeychainService.swift
//  DrawThingsStudio
//
//  Stores sensitive settings values in the macOS Keychain.
//

import Foundation
import Security
import OSLog

protocol KeychainService {
    func string(for account: String) -> String?
    func set(_ value: String, for account: String) -> Bool
    func removeValue(for account: String) -> Bool
}

final class MacKeychainService: KeychainService {
    private let service: String
    private let logger = Logger(subsystem: "com.drawthingsstudio", category: "keychain")

    init(service: String = "DrawThingsStudio") {
        self.service = service
    }

    func string(for account: String) -> String? {
        let query = baseQuery(for: account).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.warning("Keychain read failed for '\(account)': OSStatus \(status)")
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func set(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(for: account)

        let updateAttributes = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            _ = SecItemDelete(query as CFDictionary)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("Keychain write failed for '\(account)': OSStatus \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    func removeValue(for account: String) -> Bool {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(for account: String) -> [String: Any] {
        // Use the file-based login keychain (kSecUseDataProtectionKeychain omitted).
        // The data-protection keychain requires a valid access-group entitlement that
        // ad-hoc / "Sign to Run Locally" Debug builds don't have, causing SecItemAdd
        // to return errSecMissingEntitlement (−34018) silently and leaving API keys
        // unreadable on the next launch.
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
