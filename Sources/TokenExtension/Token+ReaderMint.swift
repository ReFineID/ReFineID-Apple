import CardCore

extension Token {
  /// Makes a deliberately inserted reader card the only active form of
  /// this identity on iOS.
  ///
  /// A live reader token needs no stored prime or absent-card
  /// registration. Keeping both leaves Safari two ways to name the same
  /// physical card and can make the system open the phone's NFC field
  /// while the card is already in a reader. The reader insertion is the
  /// holder's transport choice, so a successful reader mint removes only
  /// this card's contactless prime and registration. CAN and PIN1 remain
  /// stored, and the token that was just minted remains live.
  internal func supersedeStoredContactlessIdentity() {
    #if os(iOS)
      let hadPrime = PrimeStore.contains(instanceID: cardInstanceID)
      PrimeStore.forget(instanceID: cardInstanceID)
      TokenRegistrationRevoker.revoke(cardInstanceID, reason: .readerMint)
      TokenLog.notice(
        "reader mint superseded stored contactless identity; prime=\(hadPrime)"
      )
    #endif
  }
}
