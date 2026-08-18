// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && canImport(CoreNFC)
  import CardCore
  import Foundation
  import RappEngine
  /// Resolves the phone's one usable selected pair for a proxy connection.
  internal enum PhoneProxyPairSelection {
    /// Loads the selected active pair record, selecting a sole active pair
    /// on the way and clearing a stale selection.
    ///
    /// Nil means no single usable pair exists; an unloadable stored record
    /// surfaces as its load error.
    internal static func resolveSelectedPair(
      vault: RappDeviceVault
    ) throws -> RappPairRecord? {
      let pairIDs = try vault.activePairIDs()
      guard !pairIDs.isEmpty else { return nil }
      let pairID: Data
      if let selected = try vault.selectedPairID() {
        guard pairIDs.contains(selected) else {
          try vault.clearSelectedPair()
          return nil
        }
        pairID = selected
      } else if pairIDs.count == 1 {
        pairID = pairIDs[0]
        try vault.selectPair(pairID: pairID)
      } else {
        return nil
      }
      return try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
    }
  }
#endif
