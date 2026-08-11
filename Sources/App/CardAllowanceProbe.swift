//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
#if DEBUG && os(macOS)

  import CardCore
  import CryptoTokenKit
  import Dispatch
  import Foundation

  /// Reads what the card says about how often each credential may
  /// still be used.
  ///
  /// Counter-safe: the same GET DATA container the retry probe uses,
  /// read for the other numbers in it. Nothing is presented and no
  /// counter moves.
  internal enum CardAllowanceProbe {
    /// One credential's reading.
    internal struct Reading {
      /// What to call it on screen.
      internal let name: String

      /// What the card allows it.
      internal let allowances: CredentialAllowances
    }

    /// Carries the non-Sendable card onto the background queue.
    private final class UncheckedCard: @unchecked Sendable {
      let card: TKSmartCard

      init(_ card: TKSmartCard) {
        self.card = card
      }
    }

    /// Seconds to wait for the reader's slot.
    private static let slotWait: TimeInterval = 4

    /// Reads all three; empty when no card answers.
    internal static func read() -> [Reading] {
      guard let manager = TKSmartCardSlotManager.default,
        let name = manager.slotNames.first,
        let slot = Self.slot(named: name, in: manager),
        let smartCard = slot.makeSmartCard()
      else {
        return []
      }
      let carried = UncheckedCard(smartCard)
      let readings = try? SmartCardChannel(carried.card).withSession { channel in
        let operations = CardOperations(channel: channel)
        try operations.selectFineidApplication()
        return [
          ("PIN 1", CredentialRole.pin1),
          ("PIN 2", CredentialRole.pin2),
          ("PUK", CredentialRole.puk),
        ].compactMap { entry in
          (try? operations.readAllowances(role: entry.1))
            .flatMap(\.self)
            .map { allowances in
              Reading(name: entry.0, allowances: allowances)
            }
        }
      }
      return readings ?? []
    }

    /// The slot with that name, waited for synchronously.
    private static func slot(
      named name: String,
      in manager: TKSmartCardSlotManager
    ) -> TKSmartCardSlot? {
      let semaphore = DispatchSemaphore(value: 0)
      nonisolated(unsafe) var found: TKSmartCardSlot?
      manager.getSlot(withName: name) { slot in
        found = slot
        semaphore.signal()
      }
      _ = semaphore.wait(timeout: .now() + Self.slotWait)
      return found
    }
  }

#endif
