import Foundation
import Security

// MARK: - Supporting Types

/// Credentials for authenticating with a hosting backend.
public struct HostCredential: Sendable, Codable {
    /// The access key identifier (e.g. AWS access key ID).
    public var accessKeyID: String
    /// The secret access key.
    public var secretAccessKey: String
    /// An optional custom endpoint URL (e.g. for S3-compatible services).
    public var endpoint: URL?

    public init(accessKeyID: String, secretAccessKey: String, endpoint: URL? = nil) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.endpoint = endpoint
    }
}

// MARK: - KeychainService

/// Thread-safe wrapper around the macOS Keychain for storing and retrieving
/// secrets used by PodedgeCore services.
public actor KeychainService {

    /// The service identifier used for all Keychain items.
    private let service: String

    /// Creates a keychain service with the default Podedge service identifier.
    public init(service: String = "com.podedge.core") {
        self.service = service
    }

    // MARK: - Raw Data

    /// Stores arbitrary data in the Keychain under the given key.
    ///
    /// If an item with the same key already exists, it is updated.
    public func store(data: Data, forKey key: String) throws {
        // Try to delete any existing item first to avoid errSecDuplicateItem.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PodedgeError.keychainFailure(reason: "Store failed with status \(status)")
        }
    }

    /// Loads raw data from the Keychain for the given key.
    ///
    /// - Returns: The stored data, or `nil` if no item exists for the key.
    public func load(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw PodedgeError.keychainFailure(reason: "Load failed with status \(status)")
        }
    }

    /// Deletes the Keychain item for the given key.
    ///
    /// Does nothing if no item exists for the key.
    public func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PodedgeError.keychainFailure(reason: "Delete failed with status \(status)")
        }
    }

    // MARK: - Typed Credential Access

    /// Stores a ``HostCredential`` as JSON in the Keychain.
    public func storeCredential(_ credential: HostCredential, forKey key: String) throws {
        let data = try JSONEncoder().encode(credential)
        try store(data: data, forKey: key)
    }

    /// Loads a ``HostCredential`` from the Keychain.
    ///
    /// - Returns: The decoded credential, or `nil` if no item exists for the key.
    public func loadCredential(forKey key: String) throws -> HostCredential? {
        guard let data = try load(forKey: key) else { return nil }
        return try JSONDecoder().decode(HostCredential.self, from: data)
    }
}
