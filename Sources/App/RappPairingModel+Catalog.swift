// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine
  import SwiftUI

  extension RappPairingModel {
    internal func refresh() {
      Task {
        do {
          pairs = try await catalog.activePairs()
          selectedPairID = try await catalog.selectedPair()?.pairID
        } catch {
          pairs = []
          selectedPairID = nil
        }
      }
    }

    internal func revokeAll() {
      #if REFINEID_LOCAL_CARD && os(iOS)
        PhonePersistentTokenRelay.shared.stopListening()
      #endif
      Task {
        do {
          let active = try await catalog.activePairs()
          for pair in active {
            try await catalog.revoke(pairID: pair.pairID)
          }
          try await catalog.clearSelection()
          await MainActor.run {
            self.pairs = []
            self.selectedPairID = nil
            self.phase = .idle
          }
        } catch {
          await MainActor.run {
            self.refresh()
          }
        }
      }
    }
  }

#endif
