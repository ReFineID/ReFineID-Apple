#if os(macOS)

  import Foundation
  import Security

  /// The qualified time-stamp authorities, in the order they are asked.
  ///
  /// An archival signature needs a qualified timestamp; these are the
  /// services asked for one, first answer wins. The defaults are the
  /// same eu-qualified set the reference implementation ships, in the
  /// same order. URLs are configuration, not secrets: they name public
  /// services and live in preferences.
  internal enum TimestampAuthorityStore {
    /// The preferences key holding the ordered list.
    private static let key = "timestampAuthorities"

    /// The shipped set: qualified services on the EU trusted lists,
    /// best first.
    internal static let defaults: [String] = [
      "http://timestamp.sectigo.com/qualified",
      "https://timestamp.aped.gov.gr/qtss",
      "http://tss.accv.es:8318/tsa",
    ]

    /// The preferences key of the per-authority usernames.
    private static let usersKey = "timestampAuthorityUsers"

    /// The keychain service holding per-authority passwords.
    private static let passwordService = "fi.refineid.tsa-basic-auth"

    /// The preferences key of the authorities marked eIDAS-qualified.
    private static let qualifiedKey = "timestampAuthorityQualified"

    /// The configured list, or the defaults when nothing was changed.
    internal static func load() -> [String] {
      UserDefaults.standard.stringArray(forKey: Self.key) ?? Self.defaults
    }

    /// Persists an edited list; an empty list is the defaults.
    internal static func save(_ authorities: [String]) {
      if authorities.isEmpty {
        UserDefaults.standard.removeObject(forKey: Self.key)
      } else {
        UserDefaults.standard.set(authorities, forKey: Self.key)
      }
    }

    /// Forgets every edit; `load` answers the defaults again.
    internal static func restoreDefaults() {
      UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// Whether an authority is qualified for eIDAS use.
    ///
    /// The shipped set is on the EU trusted lists. A user-added service
    /// is qualified only if the user marks it so: qualification is a
    /// trusted-list fact the app cannot verify offline, so it is
    /// attested by the person who chose the service, never assumed.
    internal static func isQualified(_ authority: String) -> Bool {
      if Self.defaults.contains(authority) {
        return true
      }
      let marked = UserDefaults.standard.dictionary(forKey: Self.qualifiedKey)
      return marked?[authority] as? Bool ?? false
    }

    /// Records the user's qualification mark for an added authority.
    internal static func setQualified(_ qualified: Bool, for authority: String) {
      var marked =
        UserDefaults.standard.dictionary(forKey: Self.qualifiedKey) ?? [:]
      if qualified {
        marked[authority] = true
      } else {
        marked.removeValue(forKey: authority)
      }
      UserDefaults.standard.set(marked, forKey: Self.qualifiedKey)
    }

    /// The Basic-auth username for one authority; nil means the
    /// authority is public and no authentication is sent.
    internal static func username(for authority: String) -> String? {
      let users = UserDefaults.standard.dictionary(forKey: Self.usersKey)
      return users?[authority] as? String
    }

    /// Stores or clears one authority's Basic-auth credentials.
    ///
    /// The username lives in preferences, the password in the keychain
    /// - a credential is a secret, a service name is not. An empty
    /// username clears both, which is how a paid authority becomes a
    /// public one again. The password is write-only: nothing in the
    /// app reads it back except the signing request itself.
    internal static func saveCredentials(
      username: String,
      password: String,
      for authority: String
    ) {
      var users =
        UserDefaults.standard.dictionary(forKey: Self.usersKey) ?? [:]
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.passwordService,
        kSecAttrAccount as String: authority,
      ]
      SecItemDelete(query as CFDictionary)
      if username.isEmpty {
        users.removeValue(forKey: authority)
      } else {
        users[authority] = username
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
      }
      UserDefaults.standard.set(users, forKey: Self.usersKey)
    }
  }

#endif
