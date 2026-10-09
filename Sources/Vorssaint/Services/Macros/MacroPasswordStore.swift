// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// Where password steps keep what they type: the login Keychain, one item per
/// step, named by the step's id. A password is therefore never in preferences
/// or in a settings backup, and a macro restored on another Mac arrives with
/// its password step empty.
///
/// The Keychain ties an item to the app that made it, so reading one back is
/// silent for the same build and asks the person when a differently signed
/// copy tries.
enum MacroPasswordStore {
    private static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "com.vorssaint.utils").macro-passwords"
    }

    private static func query(for id: UUID?) -> [CFString: Any] {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                      kSecAttrService: service]
        if let id { query[kSecAttrAccount] = id.uuidString }
        return query
    }

    /// Replaces the step's password. Removing the old item first keeps the
    /// item owned by the build that is saving it now.
    @discardableResult
    static func set(_ password: String, for id: UUID) -> Bool {
        delete(id)
        var item = query(for: id)
        item[kSecValueData] = Data(password.utf8)
        item[kSecAttrLabel] = "Vorssaint macro password"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Whether the step has a password, asked without reading it, so nothing
    /// is decrypted and the Keychain never has a reason to ask.
    static func has(_ id: UUID) -> Bool {
        var query = query(for: id)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnAttributes] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// The step's password. Can wait on the person when the Keychain asks, so
    /// it is called off the main thread.
    static func password(for id: UUID) -> String? {
        var query = query(for: id)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ id: UUID) {
        SecItemDelete(query(for: id) as CFDictionary)
    }

    /// Every macro password this app saved, for a complete uninstall.
    static func deleteAll() {
        var query = query(for: nil)
        query[kSecMatchLimit] = kSecMatchLimitAll
        SecItemDelete(query as CFDictionary)
    }
}
