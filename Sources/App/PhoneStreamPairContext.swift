// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// The selected pair's rendezvous facts the holder listens under.
  ///
  /// The holder is the side whose listener the network lets everyone
  /// reach, so it publishes and the requester dials. Both derive the same
  /// name from the pairing's rendezvous token, and the requester's opening
  /// frame is the session preamble built from that token -- the arrival
  /// that says which pairing the dial is for.
  internal struct PhoneStreamPairContext {
    /// The name this pair's listener publishes.
    internal let serviceName: String

    /// The opening frame a requester of this pair dials with.
    internal let sessionPreamble: Data

    /// Resolves the listening facts for the selected pair; nil when no
    /// pair is selected or the pair cannot be loaded.
    internal static func resolve(vault: RappDeviceVault) -> Self? {
      guard
        let pair = try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault),
        let metadata = pair.metadata(),
        let preamble = try? rappStreamSessionPreamble(
          rendezvousToken: metadata.rendezvousToken
        )
      else { return nil }
      return Self(
        serviceName: StreamRendezvousName.name(sharing: metadata.rendezvousToken),
        sessionPreamble: preamble
      )
    }
  }
#endif
