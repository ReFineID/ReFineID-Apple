import Foundation

/// The card access number as the app offers it to the token driver,
/// through the app group container both are entitled to read.
///
/// The configuration store cannot carry it:
/// `TKTokenDriver.Configuration.driverConfigurations` is populated for
/// the hosting application only, and every other caller - the token
/// driver included - is handed an empty store, so a number written
/// there is unreadable exactly where it is needed. The group container
/// is the one place the app can write and the driver can read.
///
/// The number is a proximity proof printed on the card face, offered
/// while its card is present and withdrawn with it; the file holds the
/// digits for that long and no longer.
internal enum OfferedAccessNumber {
  /// The app group named in both processes' entitlements.
  private static let group = "4ZJC3SFJR2.fi.refineid"

  /// The file the digits travel in.
  private static let filename = "offered-access-number"

  /// The marker the driver leaves when the card refused the offer.
  ///
  /// The refusal happens in the token extension, which has no window
  /// to say so in; the app watches for this file and shows the
  /// refusal where the number was typed.
  private static let refusalFilename = "offered-access-number-refused"

  /// Owner read and write, nobody else.
  private static let ownerOnly = 0o600

  /// Where the file lives, or nil without the entitlement.
  private static var url: URL? {
    container?.appendingPathComponent(filename, isDirectory: false)
  }

  /// Where the refusal marker lives.
  private static var refusalUrl: URL? {
    container?.appendingPathComponent(refusalFilename, isDirectory: false)
  }

  /// The group container, or nil without the entitlement.
  private static var container: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: group)
  }

  /// The offered digits, or nil when nothing is offered.
  internal static func digits() -> String? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Offers `digits`, replacing any previous offer and clearing the
  /// previous offer's fate.
  @discardableResult
  internal static func publish(digits: String) -> Bool {
    guard let url else { return false }
    clearRefusal()
    do {
      try Data(digits.utf8).write(to: url, options: [.atomic])
      try FileManager.default.setAttributes(
        [.posixPermissions: Self.ownerOnly], ofItemAtPath: url.path)
      return true
    } catch {
      return false
    }
  }

  /// Withdraws the offer, marker included.
  internal static func withdraw() {
    clearRefusal()
    guard let url else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// Records that the card refused the offered number.
  internal static func recordRefusal() {
    guard let refusalUrl else { return }
    try? Data().write(to: refusalUrl, options: [.atomic])
  }

  /// Whether the offered number stands refused.
  internal static func refusalRecorded() -> Bool {
    guard let refusalUrl else { return false }
    return FileManager.default.fileExists(atPath: refusalUrl.path)
  }

  /// Clears the refusal, for an offer that succeeded after all.
  internal static func clearRefusal() {
    guard let refusalUrl else { return }
    try? FileManager.default.removeItem(at: refusalUrl)
  }
}
