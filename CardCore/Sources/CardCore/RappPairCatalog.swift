#if canImport(ReFineIDRapp)
  import Foundation
  import ReFineIDRapp

  /// Device-local view of active RAPP pair records. Revoked tombstones are never
  /// returned as usable pairs and pair private material never leaves Rust.
  public actor RappPairCatalog {
    /// Why a catalog read was refused.
    public enum CatalogError: Error, Sendable {
      case duplicatePairIdentifier
    }

    private let vault: RappDeviceVault
    private let clock: RappPlatformClock

    /// Builds a catalog over the vault's pair records.
    public init(
      vault: RappDeviceVault,
      clock: RappPlatformClock = RappPlatformClock()
    ) {
      self.vault = vault
      self.clock = clock
    }

    /// Lists every active pair as a summary, in stable identifier order,
    /// refusing a vault that repeats a pair identifier.
    public func activePairs() throws -> [RappPairingCoordinator.PairSummary] {
      var seen = Set<Data>()
      return try vault.activePairIDs()
        .sorted { $0.lexicographicallyPrecedes($1) }
        .map { pairID in
          guard seen.insert(pairID).inserted else {
            throw CatalogError.duplicatePairIdentifier
          }
          let pair = try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
          return RappPairingCoordinator.PairSummary(try pair.metadata())
        }
    }

    /// Loads one pair record from the vault by identifier.
    public func load(pairID: Data) throws -> RappPairRecord {
      try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
    }

    /// The summary of the selected pair, or nil when none is selected.
    public func selectedPair() throws -> RappPairingCoordinator.PairSummary? {
      guard let pairID = try vault.selectedPairID() else { return nil }
      let pair = try load(pairID: pairID)
      return RappPairingCoordinator.PairSummary(try pair.metadata())
    }

    /// Marks one pair as selected after proving it loads.
    public func select(pairID: Data) throws {
      _ = try load(pairID: pairID)
      try vault.selectPair(pairID: pairID)
    }

    /// Clears the selection without touching the pair itself.
    public func clearSelection() throws {
      try vault.clearSelectedPair()
    }

    /// Revocation is durable and intentionally has no automatic recovery path.
    public func revoke(pairID: Data) throws {
      let pair = try load(pairID: pairID)
      try pair.revoke(vault: vault, revokedAtMs: clock.wallMilliseconds())
      if try vault.selectedPairID() == pairID {
        try vault.clearSelectedPair()
      }
    }
  }
#endif
