#if canImport(Security)
import Foundation
import Security
import StremioKit

public enum KeychainError: Error, Equatable, Sendable {
    case status(Int32)
}

/// `SecretStore` backed by the Keychain (generic passwords). Items are readable after the first unlock and never leave the device.
public final class KeychainSecretStore: SecretStore, Sendable {
    private let service: String

    public init(service: String = "app.blusion.player.secrets") {
        self.service = service
    }

    /// False where the system keeps this app away from the Keychain altogether. A Mac Catalyst build signed without a
    /// provisioning profile has no application identifier, and every call fails with `errSecMissingEntitlement`.
    public static var isUsable: Bool {
        // A read finds nothing and says so; only a write is refused. Deleting an item that does not exist changes nothing.
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "app.blusion.player.probe",
                                    kSecAttrAccount as String: "probe"]
        return SecItemDelete(probe as CFDictionary) != errSecMissingEntitlement
    }

    /// The secret store for this device: the Keychain, except in a Mac build that may not use it. There the secrets go into a
    /// file only the user's account can read, next to the app's store. `usesKeychain` says which one it is.
    public static func forThisDevice() -> (store: any SecretStore, usesKeychain: Bool) {
        #if canImport(SwiftData) && (targetEnvironment(macCatalyst) || os(macOS))
        if !isUsable, let folder = PersistenceContainer.defaultStoreURL()?.deletingLastPathComponent() {
            return (FileSecretStore(fileURL: folder.appendingPathComponent("Secrets.json")), false)
        }
        #endif
        return (KeychainSecretStore(), true)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    public func get(_ key: String) async throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    public func set(_ value: String, for key: String) async throws {
        let base = baseQuery(key)
        let deleteStatus = SecItemDelete(base as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else { throw KeychainError.status(deleteStatus) }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func remove(_ key: String) async throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
#endif
