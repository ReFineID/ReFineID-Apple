// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import SwiftUI
  import UIKit

  internal extension Notification.Name {
    static let virtualIDCardEditorDidDismiss = Notification.Name(
      "fi.refineid.virtual-id-card-editor-did-dismiss")
  }

  private func virtualCardLocalized(
    _ key: StaticString,
    defaultValue: String.LocalizationValue
  ) -> String {
    String(
      localized: key,
      defaultValue: defaultValue,
      table: "VirtualIDCard")
  }

  private extension VirtualIDCard.Scenario {
    var localizedName: String {
      switch self {
      case .factoryFreshNearField:
        virtualCardLocalized(
          "scenario.factoryFreshNearField",
          defaultValue: "Factory-fresh NFC card")
      case .legacyFactoryFreshNearField:
        virtualCardLocalized(
          "scenario.legacyFactoryFreshNearField",
          defaultValue: "Factory-fresh legacy NFC card")
      case .partialActivationNearField:
        virtualCardLocalized(
          "scenario.partialActivationNearField",
          defaultValue: "Partially activated NFC card")
      case .activatedNearField:
        virtualCardLocalized(
          "scenario.activatedNearField",
          defaultValue: "Activated NFC card")
      case .registeredNearField:
        virtualCardLocalized(
          "scenario.registeredNearField",
          defaultValue: "Registered NFC identity")
      case .factoryFreshReader:
        virtualCardLocalized(
          "scenario.factoryFreshReader",
          defaultValue: "Factory-fresh reader card")
      case .activatedReader:
        virtualCardLocalized(
          "scenario.activatedReader",
          defaultValue: "Activated reader card")
      case .pin1RecoveryReader:
        virtualCardLocalized(
          "scenario.pin1RecoveryReader",
          defaultValue: "PIN 1 recovery with reader")
      case .pin2RecoveryReader:
        virtualCardLocalized(
          "scenario.pin2RecoveryReader",
          defaultValue: "PIN 2 recovery with reader")
      case .pukRecoveryRefusedReader:
        virtualCardLocalized(
          "scenario.pukRecoveryRefusedReader",
          defaultValue: "PUK recovery refused with reader")
      case .absent:
        virtualCardLocalized("scenario.absent", defaultValue: "No card")
      }
    }
  }

  private extension VirtualIDCard.Generation {
    var localizedName: String {
      switch self {
      case .activationCodeIsPuk:
        virtualCardLocalized(
          "generation.activationCodeIsPuk",
          defaultValue: "Activation code is PUK")
      case .presetActivationPIN:
        virtualCardLocalized(
          "generation.presetActivationPIN",
          defaultValue: "Separate activation PIN")
      }
    }
  }

  private extension VirtualIDCard.CertificateState {
    var localizedName: String {
      switch self {
      case .valid:
        virtualCardLocalized("certificate.valid", defaultValue: "Valid")
      case .expired:
        virtualCardLocalized("certificate.expired", defaultValue: "Expired")
      case .revoked:
        virtualCardLocalized("certificate.revoked", defaultValue: "Revoked")
      case .unreadable:
        virtualCardLocalized("certificate.unreadable", defaultValue: "Unreadable")
      case .missing:
        virtualCardLocalized("certificate.missing", defaultValue: "Missing")
      }
    }
  }

  private extension VirtualIDCard.FaultPreset {
    var localizedName: String {
      switch self {
      case .none:
        virtualCardLocalized("fault.none", defaultValue: "None")
      case .nfcDisconnectBeforeConnection:
        virtualCardLocalized(
          "fault.nfcDisconnectBeforeConnection",
          defaultValue: "NFC disconnects before connection")
      case .readerFailsCounterQuery:
        virtualCardLocalized(
          "fault.readerFailsCounterQuery",
          defaultValue: "Reader fails retry counter query")
      case .cardRemovedDuringPINChange:
        virtualCardLocalized(
          "fault.cardRemovedDuringPINChange",
          defaultValue: "Card removed during PIN change")
      case .cardRemovedDuringSignature:
        virtualCardLocalized(
          "fault.cardRemovedDuringSignature",
          defaultValue: "Card removed during document signing")
      case .responseLostAfterPIN1Activation:
        virtualCardLocalized(
          "fault.responseLostAfterPIN1Activation",
          defaultValue: "Response lost after PIN 1 activation")
      case .responseLostAfterPIN2Activation:
        virtualCardLocalized(
          "fault.responseLostAfterPIN2Activation",
          defaultValue: "Response lost after PIN 2 activation")
      case .responseLostAfterSignature:
        virtualCardLocalized(
          "fault.responseLostAfterSignature",
          defaultValue: "Response lost after document signing")
      case .certificateReadFailure:
        virtualCardLocalized(
          "fault.certificateReadFailure",
          defaultValue: "Certificate read failure")
      case .tokenPublicationFailure:
        virtualCardLocalized(
          "fault.tokenPublicationFailure",
          defaultValue: "Token publication failure")
      }
    }
  }

  /// Floating access to the editable card while a demonstration is active.
  internal struct VirtualIDCardOverlay: View {
    /// White text on the system red fill does not meet normal-text contrast.
    /// Keep the diagnostic meaning red while meeting the accessibility audit.
    private static let accessibleRed = Color(red: 0.65, green: 0, blue: 0)

    private let demoMode = DemoMode.shared
    internal let openEditor: () -> Void

    internal var body: some View {
      Button {
        // The CAN field is intentionally focused when it is the only setup
        // input. End that responder session before presenting the editor;
        // otherwise UIKit can restore a detached text input when the sheet
        // closes, making the visible field ignore both touch and VoiceOver.
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder),
          to: nil,
          from: nil,
          for: nil)
        openEditor()
      } label: {
        Label(
          virtualCardLocalized("title", defaultValue: "Virtual ID Card"),
          systemImage: "creditcard")
      }
      .buttonStyle(.borderedProminent)
      .tint(Self.accessibleRed)
      .accessibilityIdentifier("virtualCardOverlay")
      .accessibilityLabel(
        Text(virtualCardLocalized("title", defaultValue: "Virtual ID Card")))
      .accessibilityValue(Text(statusDescription))
      .accessibilityHint(
        Text(
          virtualCardLocalized(
            "openHint",
            defaultValue: "Opens the virtual card settings.")))
      .padding(.trailing, 12)
      .padding(.bottom, 64)
    }

    private var statusDescription: String {
      let card = demoMode.state.card
      switch (card.transport, card.cardPresent) {
      case (.nearField, true):
        return virtualCardLocalized(
          "status.nfcCardPresent",
          defaultValue: "NFC, card present")
      case (.nearField, false):
        return virtualCardLocalized(
          "status.nfcNoCard",
          defaultValue: "NFC, no card present")
      case (.reader, true):
        return virtualCardLocalized(
          "status.readerCardPresent",
          defaultValue: "Card reader, card present")
      case (.reader, false):
        return virtualCardLocalized(
          "status.readerNoCard",
          defaultValue: "Card reader, no card present")
      }
    }
  }

  /// Edits one complete virtual card/device snapshot and one fault plan.
  internal struct VirtualIDCardEditor: View {
    internal let demoMode: DemoMode
    internal let close: () -> Void
    @State private var draft: VirtualIDCard.Snapshot
    @State private var scenario = VirtualIDCard.Scenario.factoryFreshNearField
    @State private var faultPreset = VirtualIDCard.FaultPreset.none

    internal init(demoMode: DemoMode, close: @escaping () -> Void) {
      self.demoMode = demoMode
      self.close = close
      let current = demoMode.state
      _draft = State(initialValue: current)
      _scenario = State(
        initialValue: VirtualIDCard.Scenario.allCases.first { candidate in
          candidate.snapshot.card == current.card
            && candidate.snapshot.device == current.device
        } ?? .factoryFreshNearField)
      _faultPreset = State(
        initialValue: VirtualIDCard.FaultPreset.allCases.first { preset in
          preset.faults == current.faults
        } ?? .none)
    }

    internal var body: some View {
      NavigationStack {
        Form {
          Section(
            virtualCardLocalized("section.scenario", defaultValue: "Scenario")
          ) {
            Menu {
              ForEach(VirtualIDCard.Scenario.allCases) { candidate in
                Button {
                  scenario = candidate
                } label: {
                  if scenario == candidate {
                    Label(candidate.localizedName, systemImage: "checkmark")
                  } else {
                    Text(candidate.localizedName)
                  }
                }
                  .accessibilityIdentifier(
                    "virtualCardScenarioOption.\(candidate.rawValue)")
              }
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(
                  virtualCardLocalized(
                    "scenario.preset",
                    defaultValue: "Preset"))
                  .foregroundStyle(.primary)
                Text(scenario.localizedName)
                  .foregroundStyle(.primary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .virtualCardMenuControl()
            }
            .tint(.primary)
            .onChange(of: scenario) { _, selected in
              draft = selected.snapshot
              faultPreset = .none
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("virtualCardScenario")
            .accessibilityLabel(
              Text(
                virtualCardLocalized(
                  "scenario.accessibilityLabel",
                  defaultValue: "Virtual card scenario")))
          }
          Section(
            virtualCardLocalized("section.connection", defaultValue: "Connection")
          ) {
            Picker(
              virtualCardLocalized(
                "connection.transport",
                defaultValue: "Transport"),
              selection: $draft.card.transport
            ) {
              Text(virtualCardLocalized("transport.nfc", defaultValue: "NFC"))
                .tag(VirtualIDCard.Transport.nearField)
              Text(
                virtualCardLocalized(
                  "transport.reader",
                  defaultValue: "Card reader"))
                .tag(VirtualIDCard.Transport.reader)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("virtualCardTransport")
            Toggle(
              virtualCardLocalized(
                "connection.readerConnected",
                defaultValue: "Reader connected"),
              isOn: $draft.card.readerConnected)
              .accessibilityIdentifier("virtualCardReaderConnected")
            Toggle(
              virtualCardLocalized(
                "connection.cardPresent",
                defaultValue: "Card present"),
              isOn: $draft.card.cardPresent)
              .accessibilityIdentifier("virtualCardPresent")
            TextField(
              virtualCardLocalized(
                "connection.canShort",
                defaultValue: "CAN"),
              text: $draft.card.cardAccessNumber,
              axis: .vertical)
              .keyboardType(.numberPad)
              .virtualCardEditorField()
              .padding(.leading, 1)
              .accessibilityIdentifier("virtualCardCAN")
              .accessibilityLabel(
                Text(
                  virtualCardLocalized(
                    "connection.can",
                    defaultValue: "Card Access Number (CAN)")))
          }
          Section(
            virtualCardLocalized("section.identity", defaultValue: "Identity")
          ) {
            TextField(
              virtualCardLocalized("identity.name", defaultValue: "Name"),
              text: $draft.card.holderName,
              axis: .vertical)
              .virtualCardEditorField()
              .accessibilityIdentifier("virtualCardName")
            TextField(
              virtualCardLocalized(
                "identity.electronicClientIdentifier",
                defaultValue: "Electronic client identifier"),
              text: $draft.card.electronicClientIdentifier,
              axis: .vertical)
              .virtualCardEditorField()
              .accessibilityIdentifier("virtualCardElectronicIdentifier")
            TextField(
              virtualCardLocalized(
                "identity.tokenSerial",
                defaultValue: "Token serial"),
              text: $draft.card.tokenSerial,
              axis: .vertical)
              .virtualCardEditorField()
              .accessibilityIdentifier("virtualCardTokenSerial")
          }
          Section(
            virtualCardLocalized("section.activation", defaultValue: "Activation")
          ) {
            Picker(
              virtualCardLocalized(
                "activation.generation",
                defaultValue: "Generation"),
              selection: $draft.card.generation
            ) {
              ForEach(VirtualIDCard.Generation.allCases) { generation in
                Text(generation.localizedName).tag(generation)
              }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .virtualCardMenuControl()
            TextField(
              virtualCardLocalized(
                "activation.pin",
                defaultValue: "Activation PIN"),
              text: $draft.card.activationEntry,
              axis: .vertical)
              .keyboardType(.numberPad)
              .virtualCardEditorField()
              .accessibilityIdentifier("virtualCardActivationEntry")
            Toggle(
              virtualCardLocalized(
                "activation.pin1Factory",
                defaultValue: "PIN 1 is in factory state"),
              isOn: $draft.card.pin1.isFactoryValue)
              .accessibilityIdentifier("virtualCardPIN1Factory")
            Toggle(
              virtualCardLocalized(
                "activation.pin2Factory",
                defaultValue: "PIN 2 is in factory state"),
              isOn: $draft.card.pin2.isFactoryValue)
              .accessibilityIdentifier("virtualCardPIN2Factory")
          }
          credentialSection(
            virtualCardLocalized("credential.pin1", defaultValue: "PIN 1"),
            identifier: "virtualCardPIN1",
            valueLabel: virtualCardLocalized(
              "credential.pin1Value",
              defaultValue: "PIN 1 value"),
            attemptsLabel: virtualCardLocalized(
              "credential.pin1Attempts",
              defaultValue: "PIN 1 attempts"),
            value: $draft.card.pin1.value,
            attempts: attemptsBinding(\.pin1))
          credentialSection(
            virtualCardLocalized("credential.pin2", defaultValue: "PIN 2"),
            identifier: "virtualCardPIN2",
            valueLabel: virtualCardLocalized(
              "credential.pin2Value",
              defaultValue: "PIN 2 value"),
            attemptsLabel: virtualCardLocalized(
              "credential.pin2Attempts",
              defaultValue: "PIN 2 attempts"),
            value: $draft.card.pin2.value,
            attempts: attemptsBinding(\.pin2))
          credentialSection(
            virtualCardLocalized("credential.puk", defaultValue: "PUK"),
            identifier: "virtualCardPUK",
            valueLabel: virtualCardLocalized(
              "credential.pukValue",
              defaultValue: "PUK value"),
            attemptsLabel: virtualCardLocalized(
              "credential.pukAttempts",
              defaultValue: "PUK attempts"),
            value: $draft.card.puk.value,
            attempts: attemptsBinding(\.puk))
          Section(
            virtualCardLocalized(
              "section.certificates",
              defaultValue: "Certificates")
          ) {
            Picker(
              virtualCardLocalized(
                "certificate.authentication",
                defaultValue: "Authentication"),
              selection: $draft.card.authenticationCertificate
            ) {
              certificateChoices
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .virtualCardMenuControl()
            .accessibilityIdentifier("virtualCardAuthenticationCertificate")
            Picker(
              virtualCardLocalized(
                "certificate.signature",
                defaultValue: "Signature"),
              selection: $draft.card.signatureCertificate
            ) {
              certificateChoices
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .virtualCardMenuControl()
            .accessibilityIdentifier("virtualCardSignatureCertificate")
          }
          Section(
            virtualCardLocalized(
              "section.deviceState",
              defaultValue: "Device state")
          ) {
            TextField(
              virtualCardLocalized(
                "device.storedCan",
                defaultValue: "Stored CAN"),
              text: optionalBinding(\.storedCardAccessNumber),
              axis: .vertical)
              .keyboardType(.numberPad)
              .virtualCardEditorField()
              .accessibilityIdentifier("virtualCardStoredCAN")
            TextField(
              virtualCardLocalized(
                "device.connectedCan",
                defaultValue: "Connected CAN"),
              text: optionalBinding(\.connectedCardAccessNumber),
              axis: .vertical)
              .keyboardType(.numberPad)
              .virtualCardEditorField()
              .accessibilityIdentifier("virtualCardConnectedCAN")
            Toggle(
              virtualCardLocalized(
                "device.pin1Stored",
                defaultValue: "PIN 1 stored"),
              isOn: $draft.device.hasPin1)
              .accessibilityIdentifier("virtualCardPIN1Stored")
            Toggle(
              virtualCardLocalized(
                "device.identityCached",
                defaultValue: "Identity cached"),
              isOn: $draft.device.cachedIdentity)
              .accessibilityIdentifier("virtualCardIdentityCached")
            Toggle(
              virtualCardLocalized(
                "device.tokenRegistered",
                defaultValue: "Token registered"),
              isOn: $draft.device.tokenRegistered)
              .accessibilityIdentifier("virtualCardTokenRegistered")
            Button {
              draft.device.pendingSigningRequest.toggle()
            } label: {
              LabeledContent(
                virtualCardLocalized(
                  "device.signingPending",
                  defaultValue: "Signing request pending")
              ) {
                Image(
                  systemName: draft.device.pendingSigningRequest
                    ? "checkmark.circle.fill"
                    : "circle")
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("virtualCardSigningPending")
            .accessibilityValue(
              Text(
                virtualCardLocalized(
                  draft.device.pendingSigningRequest
                    ? "state.enabled"
                    : "state.disabled",
                  defaultValue: draft.device.pendingSigningRequest
                    ? "Enabled"
                    : "Disabled")))
          }
          Section(
            virtualCardLocalized(
              "section.nextFault",
              defaultValue: "Next deterministic fault")
          ) {
            Menu {
              ForEach(VirtualIDCard.FaultPreset.allCases) { preset in
                Button {
                  faultPreset = preset
                } label: {
                  if faultPreset == preset {
                    Label(preset.localizedName, systemImage: "checkmark")
                  } else {
                    Text(preset.localizedName)
                  }
                }
                  .accessibilityIdentifier(
                    "virtualCardFaultOption.\(preset.rawValue)")
              }
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(
                  virtualCardLocalized(
                    "fault.picker",
                    defaultValue: "Fault"))
                  .foregroundStyle(.primary)
                Text(faultPreset.localizedName)
                  .foregroundStyle(.primary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .virtualCardMenuControl()
            }
            .tint(.primary)
            .accessibilityIdentifier("virtualCardFault")
          }
        }
        .headerProminence(.increased)
        .navigationTitle(
          virtualCardLocalized("title", defaultValue: "Virtual ID Card"))
        .accessibilityIdentifier("virtualCardEditor")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(
              virtualCardLocalized("action.cancel", defaultValue: "Cancel")
            ) { close() }
              .accessibilityLabel(
                Text(
                  virtualCardLocalized(
                    "action.cancelAccessibilityLabel",
                    defaultValue: "Cancel virtual card changes")))
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(
              virtualCardLocalized("action.apply", defaultValue: "Apply")
            ) {
              draft.faults = faultPreset.faults
              demoMode.replace(with: draft)
              close()
            }
            .accessibilityIdentifier("virtualCardApply")
            .accessibilityLabel(
              Text(
                virtualCardLocalized(
                  "action.applyAccessibilityLabel",
                  defaultValue: "Apply virtual card changes")))
          }
        }
      }
    }

    private func credentialSection(
      _ title: String,
      identifier: String,
      valueLabel: String,
      attemptsLabel: String,
      value: Binding<String>,
      attempts: Binding<Int>
    ) -> some View {
      Section(title) {
        TextField(valueLabel, text: value, axis: .vertical)
          .keyboardType(.numberPad)
          .virtualCardEditorField()
          .accessibilityIdentifier("\(identifier)Value")
        Stepper(
          attemptsLabel,
          value: attempts,
          in: 0...Int(RetryCount.pristineAllowance))
          .accessibilityIdentifier("\(identifier)Attempts")
          .accessibilityValue(
            Text(
              String.localizedStringWithFormat(
                virtualCardLocalized(
                  "credential.attemptsRemaining",
                  defaultValue: "%lld attempts remaining"),
                attempts.wrappedValue)))
      }
    }

    private var certificateChoices: some View {
      ForEach(VirtualIDCard.CertificateState.allCases) { state in
        Text(state.localizedName)
          .tag(state)
          .accessibilityIdentifier(
            "virtualCardCertificateOption.\(state.rawValue)")
      }
    }


    private func attemptsBinding(
      _ keyPath: WritableKeyPath<
        VirtualIDCard.CardState,
        VirtualIDCard.CredentialState
      >
    ) -> Binding<Int> {
      Binding(
        get: {
          Int(draft.card[keyPath: keyPath].attemptsRemaining)
        },
        set: { value in
          draft.card[keyPath: keyPath].attemptsRemaining = UInt8(value)
        })
    }

    private func optionalBinding(
      _ keyPath: WritableKeyPath<VirtualIDCard.DeviceState, String?>
    ) -> Binding<String> {
      Binding(
        get: { draft.device[keyPath: keyPath] ?? "" },
        set: { entered in
          draft.device[keyPath: keyPath] = entered.isEmpty ? nil : entered
        })
    }
  }

  /// Form rows must grow with Dynamic Type instead of retaining the compact
  /// one-line text-field height. One shared treatment keeps every editable
  /// virtual-card value usable under the same accessibility settings.
  private extension View {
    func virtualCardEditorField() -> some View {
      lineLimit(1...2)
        .fixedSize(horizontal: false, vertical: true)
    }

    func virtualCardMenuControl() -> some View {
      lineLimit(1...3)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

#endif
