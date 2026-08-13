// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import Foundation
  import Observation

  /// The setup screen run against a test person instead of a card.
  ///
  /// The identity card this app reads is a legal identity document
  /// issued by the Finnish Police to one named citizen. It cannot be
  /// duplicated, lent or issued for testing, so a reviewer has no card
  /// to hold against the phone. A demonstration gives them the same
  /// screens, the same entry, the same scan sheet and an identity at the
  /// end of it.
  ///
  /// Nothing here is written down. The state lives in this object and
  /// dies with the process: a launch becomes a demonstration only
  /// through the Home Screen action, and quitting the app ends it. No
  /// launch that was not asked to demonstrate can be one.
  ///
  /// Nothing here touches the card or the system either. No certificate
  /// is read, nothing reaches ``PrimeStore`` or ``CardCredentialStore``,
  /// no token is registered, and the digits typed into the two fields
  /// stay in the fields. ``holderName`` is a string and not a
  /// certificate, so the system is offered no identity: there is none to
  /// offer.
  @MainActor
  @Observable
  internal final class DemoMode {
    /// The demonstration state of this launch.
    internal static let shared = DemoMode()

    /// Who the test identity names, in the language the phone is set to.
    ///
    /// The shape a citizen certificate carries -- surname, given name,
    /// electronic client identifier -- with a specimen number and a name
    /// each language reads as anyone at all.
    internal static var holderName: String {
      String(localized: "DOE JANE 12345678N")
    }

    /// Whether this launch is a demonstration.
    internal private(set) var isActive = false

    /// Whether the demonstration hold has produced its identity.
    internal private(set) var hasIdentity = false

    /// Whether the scan sheet is up right now.
    internal private(set) var isHolding = false

    /// Turns this launch into a demonstration.
    ///
    /// One way in and no way back out: the run stays a demonstration
    /// until the process ends.
    internal func activate() {
      isActive = true
    }

    /// Holds for a card that is not there, then names the test person.
    ///
    /// The wait and the sheet are the product's own, so what a reviewer
    /// sees is the hold the app performs rather than a drawing of one.
    internal func readTestIdentity() async {
      guard isActive, !isHolding else { return }
      isHolding = true
      #if canImport(CoreNFC)
        await DemoCardHold.run()
      #endif
      isHolding = false
      hasIdentity = true
    }

    /// Drops the test identity, leaving the launch a demonstration.
    internal func forgetIdentity() {
      hasIdentity = false
    }
  }

#endif
