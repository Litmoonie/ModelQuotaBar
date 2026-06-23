import ModelQuotaCore
import Foundation
import Security

enum DeepSeekMenuAction: Sendable {
    case setAPIKey
}

struct DeepSeekMenuValue: Sendable {
    var display: String
    var action: DeepSeekMenuAction?

    static let loading = DeepSeekMenuValue(display: "Loading", action: nil)
}

struct DeepSeekDisplayState: Sendable {
    var balance: DeepSeekMenuValue

    static let loading = DeepSeekDisplayState(balance: .loading)
}

final class DeepSeekStatusCoordinator: Sendable {
    private let balanceClient = DeepSeekBalanceClient()

    func refresh() async -> DeepSeekDisplayState {
        let balance = await fetchBalance()
        return DeepSeekDisplayState(balance: balance)
    }

    private func fetchBalance() async -> DeepSeekMenuValue {
        guard let apiKey = await DeepSeekAPIKeyStore.readPreferredAPIKey(), !apiKey.isEmpty else {
            return DeepSeekMenuValue(display: "Set API Key", action: .setAPIKey)
        }

        do {
            let balance = try await balanceClient.fetchCNYBalance(apiKey: apiKey)
            return DeepSeekMenuValue(display: formatCNY(balance), action: nil)
        } catch DeepSeekBalanceError.httpStatus(401), DeepSeekBalanceError.httpStatus(403) {
            return DeepSeekMenuValue(display: "Invalid Key", action: .setAPIKey)
        } catch {
            return DeepSeekMenuValue(display: "--", action: nil)
        }
    }
}

@MainActor
enum DeepSeekAPIKeyStore {
    private static let service = "io.github.litmoonie.modelquotabar"
    private static let account = "deepseek-api-key"
    private static var cachedAPIKey: String?
    private static var hasLoadedAPIKey = false

    static func readPreferredAPIKey() -> String? {
        if hasLoadedAPIKey {
            return cachedAPIKey
        }

        hasLoadedAPIKey = true

        if let keychainValue = try? readAPIKey(), !keychainValue.isEmpty {
            cachedAPIKey = keychainValue
            return keychainValue
        }

        let envValue = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cachedAPIKey = envValue?.isEmpty == false ? envValue : nil
        return cachedAPIKey
    }

    static func saveAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeepSeekAPIKeyStoreError.keychainWriteFailed(status)
        }

        cachedAPIKey = apiKey
        hasLoadedAPIKey = true
    }

    private static func readAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw DeepSeekAPIKeyStoreError.keychainReadFailed(status)
        }

        guard let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DeepSeekAPIKeyStoreError: Error, LocalizedError {
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed(let status):
            return "Keychain read failed: \(status)"
        case .keychainWriteFailed(let status):
            return "Keychain write failed: \(status)"
        }
    }
}

func formatCNY(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "CNY"
    formatter.currencySymbol = "¥"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 4
    return formatter.string(from: value as NSDecimalNumber) ?? "¥\(value)"
}
