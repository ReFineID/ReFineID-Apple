// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The activation form: the activation code from the issuance
  /// letter and the two new PINs.
  ///
  /// The driver classifies the card and refuses a wrong-length code
  /// before anything is spent.
  internal struct CardActivationSection: View {
    /// The keyboard path through the section.
    private enum Field {
      case entry
      case pin1
      case pin1Repeat
      case pin2
      case pin2Repeat
    }

    internal let model: CardManagementModel

    /// Whether the explicit reactivation override is offered.
    ///
    /// In the settings pane it is the escape hatch for a card the
    /// preflight misjudged; the main window's takeover appears only
    /// for a card the preflight has just called factory-fresh, where
    /// the override would be a switch with nothing to override.
    internal var showsReactivationOverride = true

    @State private var entry = ""
    @State private var newPin1 = ""
    @State private var newPin1Repeated = ""
    @State private var newPin2 = ""
    @State private var newPin2Repeated = ""
    @State private var allowReactivation = false
    @State private var pending: CredentialOperationConfirmation.Operation?
    @FocusState private var focus: Field?

    /// Whether the form asks for PIN 1: the card still waits for it,
    /// or a reactivation override puts everything back on the table.
    private var asksPin1: Bool {
      model.activationNeeds.pin1 || allowReactivation
    }

    /// Whether the form asks for PIN 2, by the same rule.
    private var asksPin2: Bool {
      model.activationNeeds.pin2 || allowReactivation
    }

    /// Ready when every entry the card still waits for can possibly
    /// be right; the exact activation-entry length is the card's to
    /// judge.
    private var isComplete: Bool {
      (Puk.minimumDigitCount...Puk.maximumDigitCount).contains(entry.count)
        && (!asksPin1
          || (Pin1.minimumDigitCount...Pin1.maximumDigitCount).contains(newPin1.count)
            && newPin1 == newPin1Repeated)
        && (!asksPin2
          || (Pin2.minimumDigitCount...Pin2.maximumDigitCount).contains(newPin2.count)
            && newPin2 == newPin2Repeated)
    }

    internal var body: some View {
      Section {
        entryRows
        if showsReactivationOverride {
          Toggle("Allow reactivation", isOn: $allowReactivation)
            .accessibilityIdentifier("managementActivationOverride")
        }
        HStack {
          Spacer()
          Button("Activate Card") {
            pending = .activate
          }
          .buttonStyle(.borderedProminent)
          .disabled(!isComplete || model.working)
          .accessibilityIdentifier("managementActivate")
        }
      }
      .task {
        // This form never placed focus at all, so its first field had
        // to be found with a pointer. See InitialFieldFocus for why the
        // window is allowed to settle first.
        await InitialFieldFocus.settle()
        focus = .entry
      }
      .confirmCredentialOperation($pending, report: model.report) { _ in
        activate()
      }
    }

    /// The secret fields, only for what the card still waits for: an
    /// interrupted activation left one PIN set, and asking for a new
    /// value it will not take invites a retry spent on nothing.
    @ViewBuilder private var entryRows: some View {
      SecureField("Activation code", text: $entry)
        .onChange(of: entry) { _, typed in
          entry = LimitedDigits.puk(typed)
        }
        .focused($focus, equals: .entry)
        .onSubmit { advance(from: .entry) }
        .accessibilityIdentifier("managementActivationEntry")
      if asksPin1 {
        SecureField("New PIN 1", text: $newPin1)
          .onChange(of: newPin1) { _, typed in
            newPin1 = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .pin1)
          .onSubmit { advance(from: .pin1) }
          .accessibilityIdentifier("managementActivationPin1")
        SecureField("New PIN 1 again", text: $newPin1Repeated)
          .onChange(of: newPin1Repeated) { _, typed in
            newPin1Repeated = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .pin1Repeat)
          .onSubmit { advance(from: .pin1Repeat) }
          .accessibilityIdentifier("managementActivationPin1Repeat")
      }
      if asksPin2 {
        SecureField("New PIN 2", text: $newPin2)
          .onChange(of: newPin2) { _, typed in
            newPin2 = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .pin2)
          .onSubmit { advance(from: .pin2) }
          .accessibilityIdentifier("managementActivationPin2")
        SecureField("New PIN 2 again", text: $newPin2Repeated)
          .onChange(of: newPin2Repeated) { _, typed in
            newPin2Repeated = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .pin2Repeat)
          .onSubmit { advance(from: .pin2Repeat) }
          .accessibilityIdentifier("managementActivationPin2Repeat")
      }
    }

    /// Return advances through the fields that are shown; on the last
    /// one it submits when complete.
    private func advance(from field: Field) {
      switch field {
      case .entry:
        if asksPin1 {
          focus = .pin1
        } else if asksPin2 {
          focus = .pin2
        } else if isComplete {
          pending = .activate
        }
      case .pin1:
        focus = .pin1Repeat
      case .pin1Repeat:
        if asksPin2 {
          focus = .pin2
        } else if isComplete {
          // Return on the last field asks the same question the
          // button asks.
          pending = .activate
        }
      case .pin2:
        focus = .pin2Repeat
      case .pin2Repeat:
        if isComplete {
          pending = .activate
        }
      }
    }

    /// Runs activation and clears the fields when the card accepted.
    private func activate() {
      guard isComplete, !model.working else { return }
      let activationEntry = entry
      let pin1Entry = asksPin1 ? newPin1 : nil
      let pin2Entry = asksPin2 ? newPin2 : nil
      let override = allowReactivation
      Task {
        let accepted = await model.activate(
          entry: activationEntry,
          newPin1: pin1Entry,
          newPin2: pin2Entry,
          allowReactivation: override
        )
        if accepted {
          entry = ""
          newPin1 = ""
          newPin1Repeated = ""
          newPin2 = ""
          newPin2Repeated = ""
          allowReactivation = false
          focus = nil
        }
      }
    }
  }

#endif
