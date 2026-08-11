// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How a card is activated, decided by its issuance date
/// (FINEID S4-1 §4.6).
///
/// Cards issued before 13 January 2026 ship with their PINs blocked;
/// the eight-digit activation code in the issuance letter is the PUK,
/// and activation is RESET RETRY COUNTER against each PIN (§4.6.1).
/// Cards issued from that date ship with both PINs set to a
/// single-use seven-digit activation PIN, and activation is CHANGE
/// REFERENCE DATA against each (§4.6.2). The scheme decides which
/// digit count the card accepts - the wrong one burns a retry - so an
/// unclassifiable card refuses activation rather than guessing.
public enum ActivationScheme: Equatable, Sendable {
  /// §4.6.1, issued before 13 January 2026: RSA citizen certificates,
  /// PINs ship blocked, the activation code is the PUK.
  case activationCodeIsPuk

  /// §4.6.2, issued from 13 January 2026: ECC citizen certificates,
  /// PINs ship set to the single-use activation PIN.
  case presetActivationPin

  /// The cutover DVV publishes, as the UTC epoch instant of its
  /// midnight.
  ///
  /// 13 January 2026. X.509 validity is expressed in UTC, so the
  /// comparison is calendar-exact.
  private static let cutoverEpochSeconds: TimeInterval = 1_768_262_400

  /// Common-name generation markers DVV's issuing CAs carry.
  private static let issuerGenerationMarkers = ["G3", "G4", "G5"]

  /// Common-name marker of DVV's organisational issuing CAs
  /// ("DVV Organisational Certificates - G4R").
  ///
  /// Refused outright: S4-1 §4.6 covers citizen cards alone, and an
  /// organization card's activation is its issuer's own process. The
  /// marker-and-suffix match below would otherwise classify it as a
  /// citizen card by accident and lend it a digit count nobody
  /// verified - the exact guess this classifier exists to refuse.
  private static let organisationalIssuerMarker = "Organisational"

  /// Common-name suffix of DVV's RSA issuing CAs.
  private static let issuerRsaSuffix = "R"

  /// Common-name suffix of DVV's ECC issuing CAs.
  private static let issuerEccSuffix = "E"

  /// The exact digit count the card accepts for the activation entry.
  ///
  /// Eight for an activation code, seven for a preset activation PIN.
  /// The card enforces the length itself and a wrong-length entry
  /// burns a retry, which is why the classification exists at all.
  public var activationEntryDigitCount: Int {
    switch self {
    case .activationCodeIsPuk:
      Puk.maximumDigitCount
    case .presetActivationPin:
      Puk.minimumDigitCount
    }
  }

  /// Classifies by the authentication certificate's notBefore date.
  ///
  /// The authoritative classifier: DVV names the cutover date itself,
  /// so this survives CA renaming. The issuance date is also printed
  /// on the card surface for human verification.
  public static func classify(issuedOn notBefore: Date) -> Self {
    notBefore.timeIntervalSince1970 >= Self.cutoverEpochSeconds
      ? .presetActivationPin
      : .activationCodeIsPuk
  }

  /// Classifies by the issuer common name, or nil to refuse.
  ///
  /// Fallback and cross-check for when the notBefore could not be
  /// read: DVV's issuing CAs end their common names with a generation
  /// marker and a key-family letter. The correlation is empirical, not
  /// protocol-guaranteed, so anything unfamiliar answers nil and the
  /// caller refuses to make activation decisions from it.
  public static func classify(issuerCommonName: String) -> Self? {
    guard !issuerCommonName.contains(Self.organisationalIssuerMarker) else {
      return nil
    }
    guard
      Self.issuerGenerationMarkers.contains(where: issuerCommonName.contains)
    else {
      return nil
    }
    if issuerCommonName.hasSuffix(Self.issuerRsaSuffix) {
      return .activationCodeIsPuk
    }
    if issuerCommonName.hasSuffix(Self.issuerEccSuffix) {
      return .presetActivationPin
    }
    return nil
  }
}
