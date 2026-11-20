import Foundation
import Security
import Synchronization

/// Where the private store's token is kept: the Keychain in the app, memory in tests.
///
/// Both calls reach the system's keychain service and may block for a moment, so the model
/// store makes them off the main actor.
public struct ModelSourceTokenStore: Sendable {
    /// The stored token, or `nil` when there is none.
    public var read: @Sendable () -> String?
    /// Stores `token`; `nil` or an empty string removes it.
    public var write: @Sendable (String?) throws -> Void

    public init(read: @escaping @Sendable () -> String?, write: @escaping @Sendable (String?) throws -> Void) {
        self.read = read
        self.write = write
    }

    /// The Keychain: one generic password of this app, on this device only, never synced
    /// and never in a backup that is restored elsewhere. Readable after the first unlock,
    /// so a download that goes on while the phone is locked can still be continued.
    public static let keychain = ModelSourceTokenStore(read: Keychain.read, write: Keychain.write)

    /// A token held in memory, for tests and previews.
    public static func inMemory(_ token: String? = nil) -> ModelSourceTokenStore {
        let stored = Mutex(token)
        return ModelSourceTokenStore(
            read: { stored.withLock { $0 } },
            write: { token in stored.withLock { $0 = token?.isEmpty == false ? token : nil } }
        )
    }

    public struct KeychainFailure: Error, Equatable, CustomStringConvertible {
        public var status: Int32
        public var description: String { "The Keychain refused the token (status \(status))." }
    }

    private enum Keychain {
        static var query: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "PageTranslationModelSource",
                kSecAttrAccount as String: "token"
            ]
        }

        static func read() -> String? {
            var query = query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func write(_ token: String?) throws {
            SecItemDelete(query as CFDictionary)
            guard let token, !token.isEmpty else { return }
            var attributes = query
            attributes[kSecValueData as String] = Data(token.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        }
    }
}
