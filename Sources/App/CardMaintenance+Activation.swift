#if os(macOS)

  import CardCore
  import Foundation
  import Security

  /// The activation flow, and reading the activation scheme off the
  /// card's own certificate.
  extension CardMaintenance {
    /// Activates the card: classifies the scheme from the
    /// authentication certificate, checks the preflight, then sets
    /// PIN1 and PIN2 - in that order, stopping if PIN1 fails.
    internal static func activate(
      entry: String,
      newPin1: String,
      newPin2: String,
      allowReactivation: Bool
    ) async -> ActivationReport? {
      let report = await onCard { operations -> ActivationReport? in
        guard let scheme = classifyScheme(operations) else { return nil }
        guard
          entry.count == scheme.activationEntryDigitCount,
          Pin1(digits: newPin1) != nil,
          Pin2(digits: newPin2) != nil
        else {
          return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
        }
        if !allowReactivation, looksActivated(operations, scheme: scheme) {
          return ActivationReport(
            scheme: scheme, pin1: .alreadyActivated, pin2: nil
          )
        }
        let first = activationStep(
          operations, scheme: scheme, entry: entry, newPin1: newPin1
        )
        guard first == .success else {
          return ActivationReport(scheme: scheme, pin1: first, pin2: nil)
        }
        let second = activationStep(
          operations, scheme: scheme, entry: entry, newPin2: newPin2
        )
        return ActivationReport(scheme: scheme, pin1: first, pin2: second)
      }
      return report.flatMap(\.self)
    }

    /// Whether the counter-safe preflight sees prior activation.
    private static func looksActivated(
      _ operations: CardOperations,
      scheme: ActivationScheme
    ) -> Bool {
      let probe = try? operations.probeRetryCounter(role: .pin1)
      let record =
        (try? operations.readPinChangeRecord(role: .pin1)) ?? .unreadable
      let readiness = ActivationPreflight.evaluate(
        scheme: scheme,
        pin1Probe: probe,
        pin1ChangeRecord: record
      )
      return readiness == .alreadyActivated
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
