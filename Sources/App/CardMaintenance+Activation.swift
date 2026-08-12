// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Security

  /// The activation flow, and reading the activation scheme off the
  /// card's own certificate.
  extension CardMaintenance {
    /// Which PINs still await their first value.
    ///
    /// Judged per PIN because an interrupted activation leaves one set
    /// and the other in its factory state (S4-1 §4.6 keeps a changed
    /// flag per PIN). The card awaits activation while either does;
    /// the set one is skipped, never set again - under the preset-PIN
    /// scheme the activation PIN stops being that PIN's current value
    /// the moment it is changed, and presenting it again would spend
    /// a retry on a value that cannot match.
    internal struct ActivationNeeds: Equatable, Sendable {
      /// Whether PIN 1 still awaits its first value.
      internal let pin1: Bool

      /// Whether PIN 2 still awaits its first value.
      internal let pin2: Bool

      /// Whether anything remains for activation to do.
      internal var any: Bool { pin1 || pin2 }
    }

    /// Activates the card.
    ///
    /// Classifies the scheme from the authentication certificate,
    /// then sets each PIN that still awaits its first value - PIN1
    /// before PIN2, stopping if PIN1 fails. A PIN already set is
    /// skipped, not set again.
    internal static func activate(
      entry: String,
      newPin1: String?,
      newPin2: String?,
      allowReactivation: Bool
    ) async -> ActivationReport? {
      let report = await onCard { operations -> ActivationReport? in
        Self.runActivation(
          operations,
          entry: entry,
          newPin1: newPin1,
          newPin2: newPin2,
          allowReactivation: allowReactivation
        )
      }
      return report.flatMap(\.self)
    }

    /// The whole activation, inside one card session.
    private static func runActivation(
      _ operations: CardOperations,
      entry: String,
      newPin1: String?,
      newPin2: String?,
      allowReactivation: Bool
    ) -> ActivationReport? {
      guard let scheme = classifyScheme(operations) else { return nil }
      guard entry.count == scheme.activationEntryDigitCount else {
        return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
      }
      let needs =
        allowReactivation
        ? ActivationNeeds(pin1: true, pin2: true)
        : Self.needs(operations, scheme: scheme)
      guard needs.any else {
        return ActivationReport(
          scheme: scheme, pin1: .alreadyActivated, pin2: nil
        )
      }
      // Every value that will be presented is judged before any is:
      // half a validation would be a step spent before the refusal.
      if needs.pin1, newPin1.flatMap({ Pin1(digits: $0) }) == nil {
        return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
      }
      if needs.pin2, newPin2.flatMap({ Pin2(digits: $0) }) == nil {
        return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
      }
      if let refusal = Self.floorRefusal(operations, scheme: scheme, needs: needs) {
        return ActivationReport(scheme: scheme, pin1: refusal, pin2: nil)
      }
      var first: Outcome = .alreadyActivated
      if needs.pin1, let fresh = newPin1 {
        first = activationStep(
          operations, scheme: scheme, entry: entry, newPin1: fresh
        )
        guard first == .success else {
          return ActivationReport(scheme: scheme, pin1: first, pin2: nil)
        }
      }
      var second: Outcome? = .alreadyActivated
      if needs.pin2, let fresh = newPin2 {
        second = activationStep(
          operations, scheme: scheme, entry: entry, newPin2: fresh
        )
      }
      return ActivationReport(scheme: scheme, pin1: first, pin2: second)
    }

    /// Which PINs of this card still await activation.
    ///
    /// Answers nil when no card is readable or its scheme cannot be
    /// classified: activation depends on knowing which entry the card
    /// expects, and offering it without that knowledge invites a
    /// wrong-length entry that spends a retry.
    internal static func activationNeeds() async -> ActivationNeeds? {
      await onCard { operations -> ActivationNeeds? in
        guard let scheme = classifyScheme(operations) else { return nil }
        return Self.needs(operations, scheme: scheme)
      }
      .flatMap(\.self)
    }

    /// The counter-safe preflight, asked once per PIN.
    private static func needs(
      _ operations: CardOperations,
      scheme: ActivationScheme
    ) -> ActivationNeeds {
      ActivationNeeds(
        pin1: pinAwaitsActivation(operations, scheme: scheme, role: .pin1),
        pin2: pinAwaitsActivation(operations, scheme: scheme, role: .pin2)
      )
    }

    /// Whether one PIN still awaits its first value.
    private static func pinAwaitsActivation(
      _ operations: CardOperations,
      scheme: ActivationScheme,
      role: CredentialRole
    ) -> Bool {
      let probe = try? operations.probeRetryCounter(role: role)
      let record =
        (try? operations.readPinChangeRecord(role: role)) ?? .unreadable
      return ActivationPreflight.evaluate(
        scheme: scheme,
        probe: probe,
        changeRecord: record
      ) == .ready
    }

    /// The floor for every credential this run will present, or nil
    /// when there is room to proceed.
    ///
    /// The activation code is checked against the PUK's counter once;
    /// a preset activation PIN is presented against each PIN it will
    /// set, so each of those counters is checked - only for the steps
    /// that will actually run.
    private static func floorRefusal(
      _ operations: CardOperations,
      scheme: ActivationScheme,
      needs: ActivationNeeds
    ) -> Outcome? {
      let roles: [CredentialRole] =
        switch scheme {
        case .activationCodeIsPuk:
          [.puk]
        case .presetActivationPin:
          [needs.pin1 ? .pin1 : nil, needs.pin2 ? .pin2 : nil].compactMap(\.self)
        }
      for role in roles {
        guard let probe = try? operations.probeRetryCounter(role: role) else {
          return .floorRefused(.refuseUnreadable)
        }
        let verdict = RetryFloor.evaluate(probeOutcome: probe)
        guard verdict == .proceed else {
          return .floorRefused(verdict)
        }
      }
      return nil
    }

    /// The PIN1 half of activation under either scheme.
    private static func activationStep(
      _ operations: CardOperations,
      scheme: ActivationScheme,
      entry: String,
      newPin1: String
    ) -> Outcome {
      switch scheme {
      case .activationCodeIsPuk:
        guard
          let code = Puk(digits: entry),
          let fresh = Pin1(digits: newPin1)
        else {
          return .invalidEntry
        }
        do {
          try operations.unblockPin1(
            puk: code.consumeForSingleTransmission(),
            new: fresh.consumeForSingleTransmission()
          )
          return .success
        } catch {
          return outcome(of: error)
        }
      case .presetActivationPin:
        guard
          let preset = Pin1(digits: entry),
          let fresh = Pin1(digits: newPin1)
        else {
          return .invalidEntry
        }
        do {
          try operations.changePin1(
            current: preset.consumeForSingleTransmission(),
            new: fresh.consumeForSingleTransmission()
          )
          return .success
        } catch {
          return outcome(of: error)
        }
      }
    }

    /// The PIN2 half of activation under either scheme.
    private static func activationStep(
      _ operations: CardOperations,
      scheme: ActivationScheme,
      entry: String,
      newPin2: String
    ) -> Outcome {
      switch scheme {
      case .activationCodeIsPuk:
        guard
          let code = Puk(digits: entry),
          let fresh = Pin2(digits: newPin2)
        else {
          return .invalidEntry
        }
        do {
          try operations.unblockPin2(
            puk: code.consumeForSingleTransmission(),
            new: fresh.consumeForSingleTransmission()
          )
          return .success
        } catch {
          return outcome(of: error)
        }
      case .presetActivationPin:
        guard
          let preset = Pin2(digits: entry),
          let fresh = Pin2(digits: newPin2)
        else {
          return .invalidEntry
        }
        do {
          try operations.changePin2(
            current: preset.consumeForSingleTransmission(),
            new: fresh.consumeForSingleTransmission()
          )
          return .success
        } catch {
          return outcome(of: error)
        }
      }
    }

    /// Classifies the activation scheme from the authentication
    /// certificate: the notBefore date is authoritative, the issuer
    /// common name the fallback, and no answer refuses activation.
    internal static func classifyScheme(
      _ operations: CardOperations
    ) -> ActivationScheme? {
      guard
        let der = try? operations.readCertificate(.authentication),
        let certificate = SecCertificateCreateWithData(nil, der as CFData)
      else {
        return nil
      }
      if let issued = notBefore(of: certificate) {
        return ActivationScheme.classify(issuedOn: issued)
      }
      return issuerCommonName(of: certificate)
        .flatMap(ActivationScheme.classify(issuerCommonName:))
    }

    /// The certificate's notBefore instant, when the platform can read
    /// it.
    private static func notBefore(of certificate: SecCertificate) -> Date? {
      let key = kSecOIDX509V1ValidityNotBefore as String
      guard
        let values =
          SecCertificateCopyValues(certificate, [key] as CFArray, nil)
          as? [String: [String: Any]],
        let seconds = values[key]?[kSecPropertyKeyValue as String] as? Double
      else {
        return nil
      }
      return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// The issuer's common name, when the platform can read it.
    private static func issuerCommonName(
      of certificate: SecCertificate
    ) -> String? {
      let key = kSecOIDX509V1IssuerName as String
      guard
        let values =
          SecCertificateCopyValues(certificate, [key] as CFArray, nil)
          as? [String: [String: Any]],
        let entries =
          values[key]?[kSecPropertyKeyValue as String] as? [[String: Any]]
      else {
        return nil
      }
      for entry in entries {
        let label = entry[kSecPropertyKeyLabel as String] as? String
        guard label == (kSecOIDCommonName as String) else { continue }
        return entry[kSecPropertyKeyValue as String] as? String
      }
      return nil
    }
  }

#endif
