import CardCore
import SwiftUI

/// What the credential screen knows and what it is allowed to do.
///
/// Nothing here ever holds a secret longer than the moment it is written:
/// the entry fields are cleared as soon as a value is stored. For PIN1
/// the model only ever reports *whether* something is stored, never what
/// it is -- a screen that can show a PIN is a screen that can leak one.
/// The card access number is the one value read back: it is printed on
/// the card face and is the holder's to see.
@MainActor
@Observable
internal final class CardCredentialsModel {
  /// What the device currently holds.
  internal private(set) var contents = CardCredentialStore.contents()

  /// The stored card access number, shown by the manager window.
  internal private(set) var storedCardAccessNumber =
    CardCredentialStore.displayedCardAccessNumber()

  /// Every card the directory knows, newest first.
  internal private(set) var cards = CardDirectory.entries()

  /// Set when the last action failed, for the holder to read.
  internal private(set) var failure: String?

  /// Refreshes what is stored, without touching PIN1.
  internal func refresh() {
    contents = CardCredentialStore.contents()
    storedCardAccessNumber = CardCredentialStore.displayedCardAccessNumber()
    cards = CardDirectory.entries()
  }

  #if os(macOS)
    /// Proves `digits` against the present card and records the pair.
    ///
    /// The number is stored only bound: the probe reads the card's
    /// serial -- the contact slot directly, the antenna through PACE
    /// with these digits -- so a wrong number is refused, not kept. A
    /// matching unbound number from older builds is retired by the
    /// successful add.
    internal func addCard(proving digits: String) async -> Bool {
      failure = nil
      guard let answer = await CardSerialProbe.read(unsealingWith: digits) else {
        failure = String(
          localized: """
            No card answered. The contact slot reads directly; a card on \
            the antenna answers only its own CAN.
            """)
        refresh()
        return false
      }
      CardDirectory.upsert(
        CardDirectory.Entry(
          serial: answer.serial.value,
          modelKey: answer.modelKey,
          model: answer.model,
          can: digits))
      if CardCredentialStore.displayedCardAccessNumber() == digits {
        CardCredentialStore.forgetCardAccessNumber()
      }
      refresh()
      return true
    }
  #endif

  /// Drops one card from the directory.
  internal func removeCard(serial: String) {
    failure = nil
    CardDirectory.remove(serial: serial)
    refresh()
  }

  /// Stores the card access number, with no gate in front.
  ///
  /// Ungated: the number is printed on the card face, so a prompt in
  /// front of storing it protected nothing and cost every setup an
  /// interruption.
  internal func saveCardAccessNumber(_ digits: String) {
    failure = nil
    let status = CardCredentialStore.save(cardAccessNumber: digits)
    if status != errSecSuccess {
      failure = String(
        localized: "Could not store the card access number (\(status)).")
    }
    refresh()
  }

  /// Stores PIN1 after the holder authenticates.
  internal func savePin1(_ digits: String) async {
    await gated(
      reason: String(localized: "Save PIN1 so this device can sign without asking")
    ) {
      let status = CardCredentialStore.save(pin1: digits)
      guard status == errSecSuccess else {
        return String(localized: "Could not store PIN1 (\(status)).")
      }
      return nil
    }
  }

  /// Stores any credentials that are not already present before minting.
  ///
  /// A nil value means that credential is already stored. The operation
  /// stops at the first failed write so the NFC field never opens with an
  /// incomplete credential set.
  internal func prepareIdentity(
    cardAccessNumber: String?,
    pin1: String?
  ) async -> Bool {
    if let cardAccessNumber {
      saveCardAccessNumber(cardAccessNumber)
      guard contents.hasCardAccessNumber else { return false }
    }
    if let pin1 {
      await savePin1(pin1)
      guard contents.hasPin1 else { return false }
    }
    refresh()
    return contents.hasCardAccessNumber && contents.hasPin1
  }

  /// Forgets the card access number, so it can be entered again.
  ///
  /// Ungated, like storing it.
  internal func forgetCardAccessNumber() {
    failure = nil
    CardCredentialStore.forgetCardAccessNumber()
    refresh()
  }

  /// Forgets PIN1, so every signature asks again.
  ///
  /// Deletion is deliberately ungated: it removes signing authority from
  /// this device and never reveals the stored value.
  internal func forgetPin1() {
    failure = nil
    CardCredentialStore.forgetPin1()
    refresh()
  }

  /// Forgets everything this device knows about the card.
  ///
  /// This clears credentials, card-directory entries, primed identities,
  /// Safari registration, and diagnostic logs without authentication.
  /// Nothing is disclosed; authority is removed.
  internal func forgetEverything() {
    failure = nil
    let outcome = CardStateReset.perform()
    CardCredentialStore.forgetAll()
    refresh()
    if !outcome.succeeded {
      failure = outcome.summary
    }
  }

  /// Runs `work` only once the holder has authenticated, then refreshes.
  ///
  /// `work` returns a message when it failed, or nil when it succeeded.
  ///
  /// This is the gate, and it is the only one: the keychain items
  /// themselves carry no access control, because the token extension has
  /// to read PIN1 while signing a request made in Safari and has no
  /// interface to answer a prompt with. PIN1 storage therefore comes
  /// through here. Deletion intentionally does not: removing a credential
  /// discloses nothing and reduces what the device can do.
  ///
  /// ``CardCredentialGate`` is also the single place a debug build can be
  /// told to skip the prompt, and nothing outside `#if DEBUG` can ask it
  /// to.
  private func gated(reason: String, work: () -> String?) async {
    failure = nil
    do {
      try await CardCredentialGate.authenticate(reason: reason)
    } catch CardCredentialGate.Refusal.unavailable {
      failure = String(
        localized: "Set a device passcode before storing card details.")
      return
    } catch {
      failure = String(localized: "Not authenticated.")
      return
    }
    failure = work()
    refresh()
  }
}
