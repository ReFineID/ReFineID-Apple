// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && canImport(CoreNFC)
  import CardCore
  import Foundation
  import RappEngine
  /// The selected pair's stream rendezvous facts needed to dial.
  internal struct PhoneStreamPairContext {
    /// Stored listener endpoints of the paired requester.
    internal let endpoints: [String]
    /// Session preamble frame built by the Rust core for this pair.
    internal let preamble: Data

    /// Resolves the dialing facts when the selected pair is bound to the
    /// stream transport profile; nil for every other pair or when the
    /// pair cannot be loaded.
    internal static func resolve(vault: RappDeviceVault) -> Self? {
      guard
        let pair = try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault),
        let metadata = try? pair.metadata(),
        metadata.transportProfile == rappStreamProfileName(),
        let storedEndpoints = metadata.streamEndpoints,
        !storedEndpoints.isEmpty,
        let sessionPreamble = try? rappStreamSessionPreamble(
          rendezvousToken: metadata.rendezvousToken
        )
      else { return nil }
      return Self(endpoints: storedEndpoints, preamble: sessionPreamble)
    }
  }
#endif
