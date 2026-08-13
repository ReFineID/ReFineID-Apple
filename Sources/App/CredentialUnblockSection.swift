// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The reset form: the PUK, and the new value twice.
///
/// The card resets the retry counter and takes the new value whether
/// or not the credential was blocked.
///
/// A wrong PUK spends the PUK itself and exhausting it is terminal
/// for the card, which is why the driver holds the retry floor
/// against the PUK's counter before anything is sent. Keyboard-first:
/// Return advances from field to field, and on the last field it
/// submits when the entries are complete.
internal struct CredentialUnblockSection: View {
  /// The keyboard path through the section.
  private enum Field {
    case puk
    case new
    case repeated
  }

  internal let model: CardManagementModel

  /// The credential this form unblocks, chosen before the form is
  /// shown rather than inside it.
  internal let target: CredentialRole

  /// The on-screen name of that credential, so the button and the
  /// fields say which one they mean.
  private var targetName: String {
    target == .pin2 ? "PIN 2" : "PIN 1"
  }

  /// The same name without its space, for accessibility identifiers
  /// that tests match exactly.
  private var identifierName: String {
    targetName.replacingOccurrences(of: " ", with: "")
  }
  @State private var puk = ""
  @State private var new = ""
  @State private var repeated = ""
  @State private var pending: CredentialOperationConfirmation.Operation?
  @FocusState private var focus: Field?

  /// The entry bounds of the targeted PIN.
  private var targetBounds: ClosedRange<Int> {
    target == .pin2
      ? Pin2.minimumDigitCount...Pin2.maximumDigitCount
      : Pin1.minimumDigitCount...Pin1.maximumDigitCount
  }

  /// Ready when the PUK and both new entries can possibly be right.
  private var isComplete: Bool {
    (Puk.minimumDigitCount...Puk.maximumDigitCount).contains(puk.count)
      && targetBounds.contains(new.count)
      && new == repeated
  }

  internal var body: some View {
    Section {
      entryRows
      if !new.isEmpty, !repeated.isEmpty, new != repeated {
        Text("The new entries differ.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Reset \(targetName)") {
          pending = .unblock(target)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!isComplete || model.working)
        .accessibilityIdentifier("managementReset\(identifierName)")
      }
    }
    .task {
      // See InitialFieldFocus: the window must settle first, or the
      // PUK typed into a freshly opened window goes nowhere.
      #if os(macOS)
        await InitialFieldFocus.settle()
      #endif
      focus = .puk
    }
    .confirmCredentialOperation($pending, report: model.report) { _ in
      unblock()
    }
  }

  /// The target picker and the three secret fields, threaded for
  /// Return.
  @ViewBuilder private var entryRows: some View {
    SecureField("PUK", text: $puk)
      .onChange(of: puk) { _, typed in
        puk = LimitedDigits.puk(typed)
      }
      .focused($focus, equals: .puk)
      .onSubmit { advance(from: .puk) }
      .accessibilityIdentifier("managementReset\(identifierName)Puk")
    SecureField("New \(targetName)", text: $new)
      .onChange(of: new) { _, typed in
        new = LimitedDigits.pin(typed)
      }
      .focused($focus, equals: .new)
      .onSubmit { advance(from: .new) }
      .accessibilityIdentifier("managementReset\(identifierName)New")
    SecureField("New \(targetName) again", text: $repeated)
      .onChange(of: repeated) { _, typed in
        repeated = LimitedDigits.pin(typed)
      }
      .focused($focus, equals: .repeated)
      .onSubmit { advance(from: .repeated) }
      .accessibilityIdentifier("managementReset\(identifierName)Repeat")
  }

  /// Return advances; on the last field it submits when complete.
  private func advance(from field: Field) {
    switch field {
    case .puk:
      focus = .new
    case .new:
      focus = .repeated
    case .repeated:
      // Return on the last field asks the same question the button
      // asks; the PUK is the one counter that cannot be restored.
      if isComplete {
        pending = .unblock(target)
      }
    }
  }

  /// Runs the unblock and clears the fields when the card accepted.
  private func unblock() {
    guard isComplete, !model.working else { return }
    let unblockTarget = target
    let pukEntry = puk
    let newEntry = new
    Task {
      if await model.unblock(target: unblockTarget, puk: pukEntry, new: newEntry) {
        puk = ""
        new = ""
        repeated = ""
        focus = nil
      }
    }
  }
}
