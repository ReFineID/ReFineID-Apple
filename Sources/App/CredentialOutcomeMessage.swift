// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// User-facing presentation shared by every credential operation.
///
/// Card operations own retry policy and return structured outcomes. This type
/// owns the corresponding wording and typography so management, activation,
/// authentication, and signing do not invent separate rejection messages.
internal enum CredentialOutcomeMessage {
  internal static func rejection(
    credentialName: String,
    remaining: RetryCount
  ) -> String {
    incorrect(credentialName: credentialName)
      + "\n"
      + String(
        localized: "You have \(remaining.attemptsRemaining) attempts remaining.")
  }

  internal static func lowAttemptRefusal() -> String {
    String(localized: "The operation was not sent.")
      + "\n"
      + String(
        localized: "ReFineID does not use either of the last two attempts.")
  }

  /// A retry-floor refusal when the card supplied the exact counter.
  /// Keeping the count here lets every credential flow use the same wording
  /// and the same two-line visual hierarchy instead of calling it a vague
  /// safety failure.
  internal static func lowAttemptRefusal(
    credentialName: String,
    remaining: RetryCount
  ) -> String {
    let detail =
      if remaining.attemptsRemaining == 1 {
        String(localized: "Only 1 attempt remains for \(credentialName).")
      } else {
        String(
          localized:
            "Only \(remaining.attemptsRemaining) attempts remain for \(credentialName).")
      }
    return String(localized: "Operation refused")
      + "\n"
      + detail
      + "\n"
      + String(
        localized: "Use another software or reset \(credentialName).")
  }

  internal static func recoveryGuidance(for role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "PIN 1 requires recovery")
        + "\n"
        + String(localized: "Reset PIN 1 with your PUK.")
    case .pin2:
      String(localized: "PIN 2 requires recovery")
        + "\n"
        + String(localized: "Reset PIN 2 with your PUK.")
    case .puk:
      preconditionFailure("PUK is the recovery credential, not a reset target")
    }
  }

  internal static func otherSoftwareRecovery() -> String {
    String(localized: "Use other software to recover the card")
      + "\n"
      + String(
        localized: "ReFineID will not use either of the final two PUK attempts.")
  }

  internal static func unrecoverableCard() -> String {
    String(localized: "The PUK is blocked")
      + "\n"
      + String(localized: "This card cannot be recovered with software.")
  }

  internal static func incorrect(credentialName: String) -> String {
    switch credentialName {
    case "PIN 1":
      String(localized: "PIN 1 is incorrect.")
    case "PIN 2":
      String(localized: "PIN 2 is incorrect.")
    case "PUK":
      String(localized: "PUK is incorrect.")
    case "activation code":
      String(localized: "Activation code is incorrect.")
    case "activation PIN":
      String(localized: "Activation PIN is incorrect.")
    default:
      "\(credentialName) is incorrect."
    }
  }
}

/// A status message with one consistent visual and accessibility hierarchy.
internal struct CredentialOutcomeText: View {
  internal enum Tone {
    case failure
    case notice
    case success
  }

  internal let message: String
  internal let tone: Tone

  internal var body: some View {
    switch tone {
    case .failure:
      emphasized(color: .red)
    case .notice:
      emphasized(color: .orange)
    case .success:
      Text(message)
        .foregroundStyle(.green)
        .bold()
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
    }
  }

  @ViewBuilder private func emphasized(color: Color) -> some View {
    let lines = message.split(
      separator: "\n",
      maxSplits: 1,
      omittingEmptySubsequences: false)

    Group {
      if lines.count == 2 {
        VStack(spacing: 4) {
          Text(String(lines[0]))
            .fontWeight(.semibold)
          Text(String(lines[1]))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
      } else {
        Text(message)
      }
    }
    .foregroundStyle(color)
    .accessibilityElement(children: .combine)
    .textSelection(.enabled)
  }
}
