import Foundation
import Security

public protocol PlatformCredentialStore: Sendable {
    func credential(for platform: AccountPlatform) throws -> PlatformCredential?
    func save(_ credential: PlatformCredential, for platform: AccountPlatform) throws
    func removeCredential(for platform: AccountPlatform) throws
}

public final class KeychainPlatformCredentialStore: PlatformCredentialStore, @unchecked Sendable {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "AudioSampleBuffer") { self.service = service }

    public func credential(for platform: AccountPlatform) throws -> PlatformCredential? {
        var query = baseQuery(for: platform)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return try JSONDecoder().decode(PlatformCredential.self, from: data)
    }

    public func save(_ credential: PlatformCredential, for platform: AccountPlatform) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(for: platform)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
        } else if status != errSecSuccess { throw KeychainError(status) }
    }

    public func removeCredential(for platform: AccountPlatform) throws {
        let status = SecItemDelete(baseQuery(for: platform) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private func baseQuery(for platform: AccountPlatform) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: platform.keychainAccount]
    }
}

public struct KeychainError: Error, Equatable, Sendable { public let status: OSStatus; public init(_ status: OSStatus) { self.status = status } }
