// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import Foundation

  /// A stamped line from the card holder, for reading a run back in order.
  ///
  /// The holder's events reach two observers on different queues, so the
  /// order two lines appear in says nothing about the order they happened.
  /// A stamp does, and it is the only way to tell an answer that arrived
  /// too late from one that arrived too early.
  internal enum HolderTrace {

    // MARK: Static Properties

    private static let started = Date()

    // MARK: Static Functions

    /// Writes one line, stamped with the seconds since the process began.
    internal static func say(_ line: String) {
      let elapsed = Date().timeIntervalSince(started)
      print(String(format: "[stream-holder %7.3f] %@", elapsed, line))
      fflush(stdout)
    }
  }

#endif
