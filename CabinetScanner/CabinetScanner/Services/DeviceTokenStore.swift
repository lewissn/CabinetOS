import Foundation
import Security

// MARK: - Device Token Store
//
// Where this device's Ops access token lives.
//
// The Keychain, not UserDefaults. The token is a bearer credential for an API
// that returns customer names, addresses, contact emails and artwork — so it
// deserves the same treatment as a password. UserDefaults is a plist in the
// app container: readable from a file-level backup and from anything that gets
// at the container, and restored onto a different device by an iCloud restore.
//
// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` matches how the scanner
// is used: the iPad sits on a bench and is unlocked once at the start of a
// shift, background sync must keep working after that, and the token must not
// travel to another device in a backup.
//
// Tokens saved by earlier builds are migrated out of UserDefaults on first
// read and the old copy is removed, so nobody has to re-enter one.

enum DeviceTokenStore {

    private static let service = "uk.co.thecabinetshop.scanner"
    private static let account = "opsDeviceAPIToken"

    /// Where builds before this one kept it.
    private static let legacyDefaultsKey = "deviceAPIToken"

    // MARK: - Reading

    static func load() -> String? {
        if let token = readKeychain() { return token }

        // One-time migration from the old home.
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: legacyDefaultsKey),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalised = normalise(legacy)
            if let normalised, save(normalised) {
                defaults.removeObject(forKey: legacyDefaultsKey)
                return normalised
            }
            return normalised
        }

        return nil
    }

    // MARK: - Writing

    /// Store a token, or clear it when `token` is nil or blank.
    /// Returns false only when the Keychain itself refused the write.
    @discardableResult
    static func save(_ token: String?) -> Bool {
        guard let normalised = normalise(token) else {
            clear()
            return true
        }

        guard let data = normalised.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Delete-then-add rather than SecItemUpdate: it is one code path for
        // both the first save and a replacement, and cannot leave two entries.
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    // MARK: - Normalising
    //
    // What arrives here is whatever was pasted from an email, a password
    // manager or a chat message. The Ops server accepts both the bare secret
    // and the whole `name:secret` line, so neither half is stripped — but a
    // pasted "Bearer " prefix, smart quotes and stray newlines are all things
    // that would otherwise produce a 401 nobody could explain.

    static func normalise(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }

        while value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Quotes a password manager or a mail client may have wrapped it in,
        // including the curly ones a mail client substitutes.
        let quotes = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
        value = value.trimmingCharacters(in: quotes)

        // Anything that is not a printable, non-space character cannot be part
        // of a token and is almost certainly a line break from the paste.
        value = value.components(separatedBy: .whitespacesAndNewlines).joined()

        return value.isEmpty ? nil : value
    }

    // MARK: - Keychain

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }

        return token.isEmpty ? nil : token
    }
}
