import Foundation

/// Version facts read from the built product itself, so the window can never
/// claim a version that is not actually bundled.
internal struct BundledVersions {
  /// Application version as "26.7.22 (124)", or nil when unreadable.
  internal let application: String?

  /// Version of the embedded CryptoTokenKit extension.
  ///
  /// Nil when the extension bundle cannot be located or read; the UI must
  /// then say so instead of guessing.
  internal let driver: String?

  /// Reads both versions from the given bundle (the main bundle in
  /// production).
  internal static func read(from bundle: Bundle) -> Self {
    Self(
      application: displayVersion(of: bundle),
      driver: driverVersion(in: bundle)
    )
  }

  private static func displayVersion(of bundle: Bundle) -> String? {
    guard
      let version = bundle.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String,
      let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    else {
      return nil
    }
    return "\(version) (\(build))"
  }

  private static func driverVersion(in bundle: Bundle) -> String? {
    guard
      let plugIns = bundle.builtInPlugInsURL,
      let contents = try? FileManager.default.contentsOfDirectory(
        at: plugIns,
        includingPropertiesForKeys: nil
      ),
      let appexURL = contents.first(where: { $0.pathExtension == "appex" }),
      let appex = Bundle(url: appexURL)
    else {
      return nil
    }
    return displayVersion(of: appex)
  }
}
