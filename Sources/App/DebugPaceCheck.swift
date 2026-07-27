#if DEBUG

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Runs one PACE handshake over an attached reader and times every step.
  ///
  /// This exists because the phone cannot answer the question it raises. A
  /// system NFC session is bounded, so a handshake that runs long is cut
  /// off part way and every measurement afterwards describes the wreckage
  /// rather than the handshake. A reader has no such bound: the card stays
  /// powered, PACE finishes however long it takes, and the timings are of
  /// the protocol rather than of a deadline.
  ///
  /// Finishing matters for its own sake too. A card counts an abandoned
  /// PACE against the card access number and answers more slowly each
  /// time, so a run that completes is also how that count is cleared.
  internal enum DebugPaceCheck {
    /// Carries a slot out of the manager's callback.
    ///
    /// `@unchecked Sendable` is sound because the semaphore below is the
    /// synchronisation: the write happens before the wait returns, and
    /// nothing else touches it.
    private final class SlotHolder: @unchecked Sendable {
      var slot: TKSmartCardSlot?
    }

    /// How many trace lines to print after the run.
    private static let tracedLines: Int = 12

    /// Names every slot, then runs the handshake on the first slot
    /// holding a card.
    internal static func perform() -> DebugModeReport {
      var lines = ["=== pace check ==="]
      guard let manager = TKSmartCardSlotManager.default else {
        return DebugModeReport(lines: lines + ["no slot manager"], succeeded: false)
      }
      let names = manager.slotNames
      lines.append("slots (\(names.count)):")
      for name in names {
        lines.append("  " + name)
      }
      guard let accessNumber = CardCredentialStore.cardAccessNumber() else {
        return DebugModeReport(
          lines: lines + ["no card access number stored; use --set-can first"],
          succeeded: false)
      }
      guard let (name, card) = Self.firstCard(in: manager, named: names) else {
        return DebugModeReport(
          lines: lines + ["no slot reported a card"], succeeded: false)
      }
      lines.append("using slot: " + name)
      return Self.run(on: card, accessNumber: accessNumber, lines: lines)
    }

    /// The first slot that has a card in it, with that card.
    private static func firstCard(
      in manager: TKSmartCardSlotManager,
      named names: [String]
    ) -> (String, TKSmartCard)? {
      for name in names {
        let slot = Self.slot(named: name, in: manager)
        guard let slot, slot.state == .validCard, let card = slot.makeSmartCard() else {
          continue
        }
        return (name, card)
      }
      return nil
    }

    /// Fetches one slot synchronously; the manager answers on a callback.
    private static func slot(
      named name: String,
      in manager: TKSmartCardSlotManager
    ) -> TKSmartCardSlot? {
      let holder = SlotHolder()
      let semaphore = DispatchSemaphore(value: 0)
      manager.getSlot(withName: name) { found in
        holder.slot = found
        semaphore.signal()
      }
      semaphore.wait()
      return holder.slot
    }

    /// Opens a session, selects master file, runs PACE, and reports.
    private static func run(
      on card: TKSmartCard,
      accessNumber: CardAccessNumber,
      lines: [String]
    ) -> DebugModeReport {
      var lines = lines
      let started = ContinuousClock.now
      do {
        try SmartCardChannel(card).withSession { channel in
          lines.append("session: open")
          // The same order the signature uses: master file first,
          // because the card refuses MSE:Set AT anywhere else.
          try? CardOperations(channel: channel).selectMasterFile()
          _ = try PaceEstablishment(channel: channel).establish(with: accessNumber)
        }
      } catch {
        lines.append(
          "pace FAILED after "
            + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
            + " ms: \(error)")
        lines.append(contentsOf: ExtensionTrace.read().suffix(Self.tracedLines))
        return DebugModeReport(lines: lines, succeeded: false)
      }
      lines.append(
        "pace OK in "
          + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now)) + " ms")
      lines.append(contentsOf: ExtensionTrace.read().suffix(Self.tracedLines))
      return DebugModeReport(lines: lines, succeeded: true)
    }
  }

#endif
