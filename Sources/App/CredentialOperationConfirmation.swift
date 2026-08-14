// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The step between filling in a management form and spending
/// something on the card.
///
/// Every task in this window costs an attempt that no software can
/// give back, and the two forms differ by a single character - which
/// is exactly how a card ends up with a new PIN 1 when its holder
/// meant PIN 2. WCAG 3.3.4 accepts reversal, checking, or
/// confirmation; nothing about a card is reversible and no entry can
/// be checked before the card sees it, so confirmation is the only
/// one of the three available here.
///
/// The alert names the operation in full. A pristine credential needs
/// no warning; retry guidance appears only after one or two mistakes,
/// while the shared retry floor prevents a third. Cancel is the default
/// and destroys every secret held by the form.
internal struct CredentialOperationConfirmation: ViewModifier {
  /// What the holder is about to do.
  internal enum Operation: Equatable {
    /// Replace a PIN, which the card grants only after checking the
    /// current value of that same PIN.
    case change(CredentialRole)

    /// Reset a blocked PIN, which the card grants only after checking
    /// the PUK.
    case unblock(CredentialRole)

    /// Set both PINs from the issuance letter, which a card accepts
    /// once.
    case activate

    /// The credential the card checks before it grants the operation,
    /// and therefore the counter this costs when the entry is wrong.
    ///
    /// Activation has no single answer: which counter it spends
    /// depends on how the card was issued, and naming the wrong one
    /// would be worse than naming none.
    internal var spends: CredentialRole? {
      switch self {
      case .change(let role):
        role
      case .unblock:
        .puk
      case .activate:
        nil
      }
    }
  }

  /// The operation awaiting a decision, or nil while the form is
  /// still being filled in.
  @Binding internal var pending: Operation?

  /// The last counter reading, so the dialog can say what is left.
  internal let report: CredentialProbeReport?

  /// Runs the operation the holder confirmed.
  internal let confirm: (Operation) -> Void

  /// Rejects the operation and destroys the form's transient secrets.
  internal let reject: (Operation) -> Void

  /// The question, which names the credential being set.
  private static func title(of operation: Operation) -> String {
    switch operation {
    case .change(let role):
      String(localized: "Confirm \(Self.name(of: role)) change?")
    case .unblock(let role):
      String(localized: "Confirm \(Self.name(of: role)) reset?")
    case .activate:
      String(localized: "Confirm card activation?")
    }
  }

  /// The affirmative action, without repeating the question mark.
  private static func actionTitle(of operation: Operation) -> String {
    switch operation {
    case .change(let role):
      String(localized: "Change \(Self.name(of: role))")
    case .unblock(let role):
      String(localized: "Reset \(Self.name(of: role))")
    case .activate:
      String(localized: "Activate Card")
    }
  }

  /// Warns only after the counter has fallen to four or three. Five is
  /// pristine and needs no commentary; one and two are refused by policy.
  private static func warning(
    for operation: Operation,
    report: CredentialProbeReport?
  ) -> String? {
    let spent = operation.spends.map(Self.name) ?? ""
    guard
      let remaining = operation.spends.flatMap({ role in
      Self.remaining(for: role, in: report)
      }),
      remaining == 4 || remaining == 3
    else {
      return nil
    }
    switch operation {
    case .change:
      return String(
        localized: """
          A wrong current \(spent) spends one attempt. \
          \(remaining) attempts remain.
          """
      )
    case .unblock:
      return String(
        localized: """
          A wrong \(spent) spends one attempt. \(remaining) attempts remain. \
          Exhausting the \(spent) cannot be undone by software.
          """
      )
    case .activate:
      return nil
    }
  }

  /// The reported count for one credential, if the card gave one.
  private static func remaining(
    for role: CredentialRole,
    in report: CredentialProbeReport?
  ) -> Int? {
    let outcome: RetryProbeOutcome? =
      switch role {
      case .pin1:
        report?.pin1
      case .pin2:
        report?.pin2
      case .puk:
        report?.puk
      }
    guard case .remaining(let count) = outcome else { return nil }
    return Int(count.attemptsRemaining)
  }

  /// The on-screen name, written the way the card documentation
  /// writes it.
  private static func name(of role: CredentialRole) -> String {
    switch role {
    case .pin1:
      "PIN 1"
    case .pin2:
      "PIN 2"
    case .puk:
      "PUK"
    }
  }
  internal func body(content: Content) -> some View {
    content
      .alert(
        // Verbatim: the title is already a translated sentence, and
        // handing it over as a key would put the English one, and an
        // empty string, into the catalogue as things to translate.
        Text(verbatim: pending.map(Self.title) ?? ""),
        isPresented: Binding(
          get: { pending != nil },
          set: { shown in
            if !shown, let operation = pending {
              pending = nil
              reject(operation)
            }
          }
        ),
        presenting: pending
      ) { operation in
        Button(Self.actionTitle(of: operation)) {
          pending = nil
          confirm(operation)
        }
        .accessibilityIdentifier("managementConfirm")
        Button("Cancel", role: .cancel) {
          pending = nil
          reject(operation)
        }
        .accessibilityIdentifier("managementCancel")
      } message: { operation in
        if let warning = Self.warning(for: operation, report: report) {
          Text(warning)
        }
      }
  }
}

extension View {
  /// Puts an irreversible card operation to the holder before it is
  /// sent.
  internal func confirmCredentialOperation(
    _ pending: Binding<CredentialOperationConfirmation.Operation?>,
    report: CredentialProbeReport?,
    reject: @escaping (CredentialOperationConfirmation.Operation) -> Void,
    confirm: @escaping (CredentialOperationConfirmation.Operation) -> Void
  ) -> some View {
    modifier(
      CredentialOperationConfirmation(
        pending: pending,
        report: report,
        confirm: confirm,
        reject: reject
      )
    )
  }
}
