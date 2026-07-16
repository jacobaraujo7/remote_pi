import Foundation
import Security

/// Thin wrapper around the iOS Keychain that stores a single
/// generic-password item with `kSecAttrSynchronizable = true`, so the
/// blob propagates across devices of the same Apple ID via iCloud
/// Keychain.
///
/// No `SecKey`, no Secure Enclave — the blob is opaque bytes. Crypto
/// material lives inside the blob (encoded by the Dart side); we only
/// move bytes through the iCloud sync surface.
///
/// `kSecAttrSynchronizable` is "all or nothing" at query time: a query
/// that omits or sets it differently from how the item was stored will
/// match no item, even if the service/account match. Every method here
/// passes the flag explicitly to avoid that surprise.
final class KeychainSyncStore {
    /// All errors funnel through this enum so the plugin can map them
    /// to FlutterError codes.
    enum StoreError: Error {
        case syncUnavailable(String)
        case osStatus(OSStatus, String)
    }

    private let service = "dev.remotepi.owner.identity"
    private let account = "singleton"

    /// Loads the current blob, or nil if not yet stored.
    func load() throws -> Data? {
        var query: [String: Any] = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue!
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var raw: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &raw)
        switch status {
        case errSecSuccess:
            return raw as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw StoreError.osStatus(status, "SecItemCopyMatching failed")
        }
    }

    /// Saves the blob. Uses update-or-add so re-saving doesn't fail
    /// with `errSecDuplicateItem`.
    func save(blob: Data) throws {
        let update = [kSecValueData as String: blob] as CFDictionary
        var query = baseQuery()
        let updateStatus = SecItemUpdate(query as CFDictionary, update)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // First save — insert.
            query[kSecValueData as String] = blob
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw StoreError.osStatus(addStatus, "SecItemAdd failed")
            }
        default:
            throw StoreError.osStatus(updateStatus, "SecItemUpdate failed")
        }
    }

    /// Wipes the entry (also propagates the delete through iCloud).
    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        // Treat "not found" as success — idempotent.
        if status != errSecSuccess && status != errSecItemNotFound {
            throw StoreError.osStatus(status, "SecItemDelete failed")
        }
    }

    /// Whether the synchronizable Keychain surface is usable right now.
    ///
    /// Deliberately NOT `FileManager.ubiquityIdentityToken` — that is
    /// the iCloud *Drive/ubiquity* signal and is always nil unless the
    /// app ships an iCloud entitlement (which this app does not). Using
    /// it locked every App Store user out at "Sync required" even with
    /// iCloud + iCloud Keychain fully enabled (issue #39).
    ///
    /// iCloud Keychain items (`kSecAttrSynchronizable`) need no iCloud
    /// entitlement, and Apple exposes no public "is iCloud Keychain
    /// on?" query — the save/load error path is the real check. So the
    /// pre-flight just probes that the Keychain answers our query at
    /// all: success or item-not-found both mean "usable"; only hard
    /// errors (keychain not available, interaction not allowed) report
    /// false.
    func isSyncAvailable() -> Bool {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]
    }
}
