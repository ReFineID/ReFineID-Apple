import Foundation
import Security

/// A bounded period during which the token extension may sign without
/// asking for PIN1 again.
///
/// ``Pin1Cache`` already spares the holder re-typing across the several
/// signatures of one login, but it lives in the extension's memory and
/// starts empty. On the system-driven path there is nothing to fill it:
/// the extension is asked for a signature with no interface to ask for a
/// PIN with, so a login that needs one simply fails. This window is how
/// the first PIN gets there. The app authenticates the holder with Face
/// ID, opens the window, and the extension may then use PIN1 until it
/// goes idle.
///
/// The rules are the same fifteen minutes ``Pin1CachePolicy`` uses, and
/// they slide: each use restamps the window, so an active session stays
/// open and an abandoned phone closes itself. In practice the system
/// reaps the extension long before that, which only shortens the exposure.
///
/// This copy is deliberately *not* behind a biometric access control,
/// because the extension has no way to answer a prompt while signing a
/// request made in Safari. That is the whole trade: PIN1's stored master
/// copy stays gated by Face ID, and this derived copy is readable without
/// asking but exists only for a quarter of an hour of inactivity. It is
/// still `WhenUnlockedThisDeviceOnly` and non-synchronizable, so it is
/// never backed up, never restored elsewhere, and never sent to iCloud.
public enum Pin1SigningWindow {
  /// Wire form. `lastUsed` is wall clock because the window has to
  /// outlive the processes that use it, and a monotonic clock does not.
  private struct Window: Codable {
    var pin1: String
    var lastUsed: Date
  }

  /// Keychain service the open window lives under.
  private static let service = "fi.refineid.pin1window"

  /// Single well-known account: one window per device.
  private static let account = "current"

  /// Opens the window with a PIN the holder has just authenticated for.
  @discardableResult
  public static func open(pin1 digits: String, now: Date = Date()) -> Bool {
    guard Pin1(digits: digits) != nil else { return false }
    return write(Window(pin1: digits, lastUsed: now))
  }

  /// Closes the window immediately.
  public static func close() {
    SecItemDelete(query() as CFDictionary)
  }

  /// How long an open window has been idle, or nil when none is open.
  ///
  /// Deliberately does not restamp and does not close an expired window:
  /// a diagnostics screen asking how idle the window is must not keep it
  /// alive, and must not change the state the next login will meet. That
  /// is the whole difference between this and ``isOpen(now:)``.
  public static func idle(now: Date = Date()) -> Duration? {
    guard let window = read(), isLive(window, now: now) else { return nil }
    return .seconds(now.timeIntervalSince(window.lastUsed))
  }

  /// Whether a usable window is open, without consuming it.
  public static func isOpen(now: Date = Date()) -> Bool {
    guard let window = read() else { return false }
    guard isLive(window, now: now) else {
      close()
      return false
    }
    return true
  }

  /// The PIN1 to sign with, restamping the window, or nil when it has
  /// gone idle or was never opened.
  ///
  /// An expired window is deleted rather than merely refused, so a
  /// forgotten PIN does not sit on the device waiting for a clock to
  /// come back around.
  public static func pin1(now: Date = Date()) -> Pin1? {
    guard let window = read() else { return nil }
    guard isLive(window, now: now), let pin = Pin1(digits: window.pin1) else {
      close()
      return nil
    }
    write(Window(pin1: window.pin1, lastUsed: now))
    return pin
  }

  /// Whether a window last used at `lastUsed` is still live at `now`.
  ///
  /// The rule, and not the keychain around it, is what can be wrong
  /// here, so it is a pure function: the tests exercise this directly,
  /// which they could not do through storage that needs an entitlement.
  ///
  /// A `lastUsed` in the future means the clock moved backwards, which
  /// is exactly how a stale window would be revived; treat it as dead.
  public static func isLive(lastUsed: Date, now: Date) -> Bool {
    let idle = now.timeIntervalSince(lastUsed)
    guard idle >= 0 else { return false }
    return Duration.seconds(idle) <= Pin1CachePolicy.idleTimeout
  }

  private static func isLive(_ window: Window, now: Date) -> Bool {
    isLive(lastUsed: window.lastUsed, now: now)
  }

  private static func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private static func read() -> Window? {
    var query = self.query()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return try? JSONDecoder().decode(Window.self, from: data)
  }

  @discardableResult
  private static func write(_ window: Window) -> Bool {
    guard let data = try? JSONEncoder().encode(window) else { return false }
    close()
    var attributes = query()
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] =
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }
}
