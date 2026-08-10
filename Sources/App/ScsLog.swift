#if os(macOS)
  import OSLog

  /// Diagnostic logging for the localhost SCS.
  ///
  /// Follows the token extension's line twice over: lengths, status
  /// words and control flow only - never a PIN, a document, or a
  /// signature value - and development builds only. A production
  /// build writes no diagnostics; the autoclosure keeps it from even
  /// building the line.
  internal enum ScsLog {
    #if DEBUG
      private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "scs")
    #endif

    /// Records ordinary control flow.
    internal static func info(_ message: @autoclosure () -> String) {
      #if DEBUG
        Self.logger.info("\(message(), privacy: .public)")
      #endif
    }

    /// Records a failure worth investigating.
    internal static func error(_ message: @autoclosure () -> String) {
      #if DEBUG
        Self.logger.error("\(message(), privacy: .public)")
      #endif
    }
  }
#endif
