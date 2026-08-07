#if os(macOS)
  import OSLog

  /// Diagnostic logging for the localhost SCS.
  ///
  /// Follows the token extension's line: lengths, status words, and
  /// control flow only - never a PIN, a document, or a signature
  /// value.
  internal enum ScsLog {
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "scs")

    /// Records ordinary control flow.
    internal static func info(_ message: String) {
      Self.logger.info("\(message, privacy: .public)")
    }

    /// Records a failure worth investigating.
    internal static func error(_ message: String) {
      Self.logger.error("\(message, privacy: .public)")
    }
  }
#endif
