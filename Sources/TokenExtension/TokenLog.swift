import CardCore
import Foundation
import OSLog

/// Diagnostic logging for the token extension.
///
/// The extension runs inside ctkd, where no debugger or probe reaches it,
/// so this is the only window into the real createToken/sign invocations.
/// Every line goes to os.Logger AND is appended to a file in the
/// extension's tmp dir, which is pullable over wireless without a USB swap:
///   xcrun devicectl device copy from --device <id> \
///     --domain-type appDataContainer --domain-identifier fi.refineid.ReFineID.token \
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

  /// A line for the shared trace only, recorded but not written out yet.
  ///
  /// The lines taken inside a live field take this cheap path on purpose.
  /// A contactless signature runs in a field that lasts about two
  /// seconds, and a file write plus a keychain round trip per APDU would
  /// spend that field on narrating itself; ``ExtensionTrace/record(_:)``
  /// only touches memory. They reach the shared item at the next ordinary
  /// log line, which on every path here is the one that ends the
  /// operation.
  internal static func trace(_ message: String) {
    ExtensionTrace.record(message)
  }

  /// Writes out everything ``trace(_:)`` has recorded.
  ///
  /// Called where an operation ends without a log line of its own, so a
  /// trace is never left stranded in a process ctkd is about to reap.
  internal static func flush() {
    ExtensionTrace.flush()
  }

  /// Appends one timestamped line to the pullable file log, and to the
  /// trace the containing app can read.
  ///
  /// The file above lives in this extension's own container, which no other
  /// process may open, so on iOS 26 - where `log stream --device` is gone
  /// and `log collect` fails - it is unreachable from a cable. Every line
  /// therefore also goes to `ExtensionTrace`, a bounded keychain buffer in
  /// the shared access group, which the app prints on demand. Both carry
  /// the same already-sanitized text.
  private static func append(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    ExtensionTrace.append(line)
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
