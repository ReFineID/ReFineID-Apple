import CardCore
import Testing

@Suite
internal struct Pin1CacheTests {
  private func serial(_ value: String) -> TokenSerial {
    guard let serial = TokenSerial(value: value) else {
      fatalError("test serial must be valid")
    }
    return serial
  }

  private func pin(_ digits: String) -> Pin1 {
    guard let pin = Pin1(digits: digits) else {
      fatalError("test PIN must be valid")
    }
    return pin
  }

  private func fingerprint(_ digits: String, _ serial: TokenSerial) -> PinFingerprint {
    pin(digits).fingerprint(boundTo: serial)
  }

  /// True when the optional carried a PIN (consuming it either way).
  private func present(_ candidate: consuming Pin1?) -> Bool {
    if let value = candidate {
      _ = value
      return true
    }
    return false
  }

  @Test
  internal func storeThenCheckoutReturnsTheSameDigits() {
    let cache = Pin1Cache()
    let card = serial("AABBCC01")
    cache.store(pin("123456"), serial: card)
    guard let reused = cache.checkout(serial: card, pristine: true) else {
      Issue.record("expected a cached PIN1")
      return
    }
    let reusedFingerprint = reused.fingerprint(boundTo: card)
    #expect(reusedFingerprint == fingerprint("123456", card))
  }

  @Test
  internal func checkoutRefusesADifferentCard() {
    let cache = Pin1Cache()
    cache.store(pin("123456"), serial: serial("CARD-A"))
    let wrongCard = present(cache.checkout(serial: serial("CARD-B"), pristine: true))
    #expect(!wrongCard)
  }

  @Test
  internal func nonPristineCheckoutLatchesCachingOffUntilReset() {
    let cache = Pin1Cache()
    let card = serial("AABBCC02")
    cache.store(pin("123456"), serial: card)
    // A non-pristine reading refuses the reuse and latches caching off.
    let nonPristine = present(cache.checkout(serial: card, pristine: false))
    #expect(!nonPristine)
    // A later pristine store then checkout stays off until reset.
    cache.store(pin("123456"), serial: card)
    let stillLatched = present(cache.checkout(serial: card, pristine: true))
    #expect(!stillLatched)
    // reset (fresh token) re-enables caching.
    cache.reset()
    cache.store(pin("123456"), serial: card)
    let afterReset = present(cache.checkout(serial: card, pristine: true))
    #expect(afterReset)
  }

  @Test
  internal func expiredEntryReturnsNil() {
    let cache = Pin1Cache(idleWindow: .zero)
    let card = serial("AABBCC03")
    cache.store(pin("123456"), serial: card)
    let aged = present(cache.checkout(serial: card, pristine: true))
    #expect(!aged)
  }

  @Test
  internal func clearDropsTheEntryButKeepsCachingEnabled() {
    let cache = Pin1Cache()
    let card = serial("AABBCC04")
    cache.store(pin("123456"), serial: card)
    cache.clear()
    let afterClear = present(cache.checkout(serial: card, pristine: true))
    #expect(!afterClear)
    // Still enabled: a fresh store is usable.
    cache.store(pin("654321"), serial: card)
    guard let reused = cache.checkout(serial: card, pristine: true) else {
      Issue.record("expected a cached PIN1 after re-store")
      return
    }
    let reusedFingerprint = reused.fingerprint(boundTo: card)
    #expect(reusedFingerprint == fingerprint("654321", card))
  }
}
