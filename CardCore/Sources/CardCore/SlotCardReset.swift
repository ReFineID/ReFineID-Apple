#if os(macOS)

  import CryptoTokenKit
  import Foundation
  import PcscCardReset

  /// Resets a present card at PC/SC level, which makes the system
  /// re-evaluate what the card is.
  ///
  /// `ctkd` remembers "no driver can handle this card" for as long as
  /// the card sits still, so a number offered after a failed mint
  /// changes nothing until the card arrives again. Lifting the card
  /// and laying it back is the physical version of this call; the
  /// reset is the same state change in software, and the
  /// re-evaluation that follows is what reads the fresh offer.
  public enum SlotCardReset {
    /// Resets every present card on a contactless interface, and
    /// answers whether at least one reset went through.
    ///
    /// Contactless only: this is called for a sealed card the system
    /// has given up on, and a card something is using must never be
    /// reset under it.
    public static func resetContactlessCards() -> Bool {
      guard let manager = TKSmartCardSlotManager.default else { return false }
      var anyReset = false
      for name in manager.slotNames {
        guard
          let slot = manager.slotNamed(name),
          slot.state == .validCard,
          let answer = slot.atr?.bytes,
          AnswerToReset.indicatesContactlessInterface(bytes: answer)
        else { continue }
        if CardCoreResetCard(name) {
          anyReset = true
        }
      }
      return anyReset
    }
  }

#endif
