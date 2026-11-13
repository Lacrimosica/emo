import Foundation
import Security

/// API keys live in the macOS Keychain, never in the database or UserDefaults.
public struct KeychainStore: Sendable {
    public enum Account: String, Sendable {
        case claudeAPIKey = "claude-api-key"
        case ollamaAPIKey = "ollama-api-key"
    }

    private let service: String

    public init(service: String = "dev.emo.Emo") {
        self.service = service
    }

    public func read(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `value`, or deletes the item when `value` is empty.
    public func write(_ value: String, for account: Account) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var item = baseQuery(account)
        item[kSecValueData as String] = Data(trimmed.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LLMError.transport("Couldn't save the key to the Keychain (\(status)).")
        }
    }

    private func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }
}
