import Foundation
import OSLog

/// Diagnostic logging for the token extension.
///
/// The extension runs inside ctkd, where no debugger or probe reaches it,
/// so this is the only window into the real createToken/sign invocations.
/// Every line goes to os.Logger AND is appended to a file in the
/// extension's tmp dir, which is pullable over wireless without a USB swap:
///   xcrun devicectl device copy from --device <id> \
///     --domain-type appDataContainer --domain-identifier fi.refineid.ReFineID.ctk \
///     --source tmp/refineid-token-extension.log --destination /tmp/trace.log
/// No PIN, PUK, full serial, or certificate content is ever logged - only
/// lengths, status words, and control flow (release plan section 4.3).
internal enum TokenLog {
  private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "ctk")
  private static let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("refineid-token-extension.log")

  internal static func info(_ message: String) {
    logger.info("\(message, privacy: .public)")
    append("INFO \(message)")
  }

  /// Notice level persists to the on-device log store, so a trace of the
  /// load-bearing control flow (supports/sign/beginAuth) survives long
  /// enough to be collected after a Safari attempt; `info` is memory-only.
  internal static func notice(_ message: String) {
    logger.notice("\(message, privacy: .public)")
    append("NOTICE \(message)")
  }

  internal static func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
    append("ERROR \(message)")
  }

  /// Appends one timestamped line to the pullable file log.
  private static func append(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = Data("[\(stamp)] \(line)\n".utf8)
    if let handle = try? FileHandle(forWritingTo: fileURL) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: fileURL, options: .atomic)
    }
  }
}
