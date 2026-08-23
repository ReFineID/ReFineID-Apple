// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardCredentialsView {
  #if os(iOS)
    private var verifyRouteButton: some View {
      Button {
        showsDocumentVerify = true
      } label: {
        navigationRow(
          String(
            localized: "verify.title",
            defaultValue: "Verify",
            table: "DocumentSigning")
        ) {
          Image(systemName: Self.verificationSymbolName)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("verifyDocuments")
    }

    private var signRouteButton: some View {
      Button {
        synchronizeIdentityState()
        transition(.openDocumentSigning)
      } label: {
        navigationRow(
          String(
            localized: "signing.title",
            defaultValue: "Sign",
            table: "DocumentSigning")
        ) {
          Image(systemName: "signature")
            .foregroundStyle(
              signingAvailable
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(.secondary)
            )
            .accessibilityHidden(true)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("signDocuments")
      .disabled(!signingAvailable)
    }

    internal var signingSection: some View {
      Section {
        verifyRouteButton
        if offersNearField || hasReaderIdentity {
          signRouteButton
        }
      } header: {
        compactSectionHeader(
          verbatim: String(
            localized: "signing.document",
            defaultValue: "Document",
            table: "DocumentSigning"))
      }
    }

    #if REFINEID_REMOTE_CARD
      private var remoteRouteButton: some View {
        Button {
          openRemoteReader()
        } label: {
          navigationRow(String(localized: "Remote")) {
            Image(
              systemName: remoteCardAvailable
                ? "key.radiowaves.forward"
                : "key.radiowaves.forward.slash"
            )
            .foregroundStyle(
              remoteCardAvailable
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(.secondary)
            )
            .accessibilityHidden(true)
          }
        }
        .tint(.primary)
        .accessibilityIdentifier("remoteCard")
        .disabled(!remoteCardAvailable)
      }
    #endif

    private var cardManagementButton: some View {
      Button {
        openCardManagement()
      } label: {
        navigationRow(
          String(localized: "Personal Identification Numbers (PINs)")
        ) {
          CredentialRetryHealthKey(
            level: retryHealth.level,
            systemName: "key.2.on.ring",
            routeAvailable: managementAvailable)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("manageCard")
      .disabled(!managementAvailable)
    }

    internal var cardSection: some View {
      Section {
        #if REFINEID_REMOTE_CARD
          if offersNearField {
            remoteRouteButton
          }
        #endif
        if offersNearField || hasReaderIdentity {
          cardManagementButton
        }
      } header: {
        compactSectionHeader("Card")
      }
    }

    internal var readerIdentitySection: some View {
      CardReaderIdentitySection(
        holders: readerHolders,
        hasPin1: model.contents.hasPin1,
        onForgetPin1: {
          CardCredentialStore.forgetPin1()
          model.refresh()
        },
        onSavePin1: { pin1 in
          await CardReaderPinStore.verifyAndSave(pin1, model: model)
        }
      )
    }
  #endif

  #if os(iOS) && REFINEID_REMOTE_CARD
    @ViewBuilder private var remoteIdentityContent: some View {
      switch remoteModel.phase {
      case .connecting:
        ProgressView()
      case .identity(let holder):
        HStack(spacing: Self.holderActionSpacing) {
          Text(holder)
            .textSelection(.enabled)
            .accessibilityIdentifier("remoteCardHolder")
          Button {
            remoteModel.forget()
          } label: {
            Image(systemName: "minus.circle.fill")
              .foregroundStyle(.red)
          }
          .buttonStyle(.borderless)
          .accessibilityIdentifier("forgetRemoteIdentity")
          .accessibilityLabel(String(localized: "Forget identity"))
        }
      case .idle, .failed:
        Button(String(localized: "Connect Remote Reader")) {
          if remoteModel.hasPair {
            remoteModel.connect()
          } else {
            openRemoteReader()
          }
        }
        .accessibilityIdentifier("connectRemoteReader")
      }
    }

    internal var remoteReaderSection: some View {
      Section {
        LabeledContent {
          remoteIdentityContent
        } label: {
          PersonRowLabel(configured: remoteModel.holder != nil)
        }
        if remoteModel.phase == .failed {
          Text(remoteModel.failureText ?? String(localized: "The remote card could not be read."))
            .foregroundStyle(.secondary)
        }
      } header: {
        compactSectionHeader("Identity")
      }
      .onValueChange(of: remoteModel.needsFreshPairing) { needsFresh in
        if needsFresh {
          remoteModel.acknowledgeFreshPairing()
          openRemoteReader()
        }
      }
    }
  #else
    internal var remoteReaderSection: some View {
      EmptyView()
    }
  #endif

  #if os(macOS)
    internal var readerIdentitySection: some View {
      EmptyView()
    }
  #endif

  @ViewBuilder internal var createIdentitySection: some View {
    Section {
      cardAccessNumberRow
    } header: {
      compactSectionHeader("Connect Identity Card")
    }
    Section {
      pin1Row
    } header: {
      compactSectionHeader("Browser authentication")
    }
    if hasConfiguredCard {
      #if REFINEID_LOCAL_CARD && os(iOS)
        if #available(iOS 26.0, *) {
          Section {
            CardRegistrationSections(
              canPrepareCredentials: canPrepareIdentity,
              isDemonstration: isDemonstration,
              enteredPin1: enteredPin1,
              cardAccessNumber: registrationCardAccessNumber,
              storeCardAccessNumber: storeProvenCardAccessNumber,
              storeVerifiedPin1: storeVerifiedPin1,
              clearPin1Entry: clearPin1Entry,
              onRegistrationStarted: {
                transition(.startConfiguredBrowserRegistration)
              },
              onRegistrationFinished: { succeeded in
                finishBrowserRegistration(succeeded: succeeded)
              },
              isRegistered: $isRegistered,
              model: primingModel
            )
            .id(registrationReset)
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        if let failure = primingModel.failure {
          Section {
            CredentialOutcomeText(message: failure, tone: .failure)
              .accessibilityIdentifier("primeFailureMessage")
          }
        }
      #endif
    } else {
      Section {
        Button {
          connectIdentityCard()
        } label: {
          BrowserAuthenticationEnableLabel()
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          !isCardAccessNumberEntryComplete
            || !isPin1EntryComplete
            || model.isConnecting
        )
        .accessibilityIdentifier("connectCard")
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    }
  }

  @ViewBuilder internal var cardAccessNumberRow: some View {
    #if os(iOS)
      HStack {
        TextField(
          "Card Access Number (CAN)",
          text: $cardAccessNumberEntry
        )
        .font(.body)
        .keyboardType(.numberPad)
        .textContentType(nil)
        .focused($isCardAccessNumberFieldFocused)
        .accessibilityIdentifier("cardAccessNumberField")
        .onAppear {
          DispatchQueue.main.async {
            guard shouldFocusCardAccessNumber else { return }
            isCardAccessNumberFieldFocused = true
          }
        }
        .onValueChange(of: cardAccessNumberEntry) { typed in
          cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
        }
        #if REFINEID_LOCAL_CARD && os(iOS)
          canScanButton
        #endif
      }
    #else
      TextField(
        "Card Access Number (CAN)",
        text: $cardAccessNumberEntry
      )
      .font(.body)
      .accessibilityIdentifier("cardAccessNumberField")
      .onValueChange(of: cardAccessNumberEntry) { typed in
        cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
      }
    #endif
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    @ViewBuilder private var canScanButton: some View {
      if CardAccessNumberScanner.isAvailable {
        Button {
          scannerTorchEnabled = false
          isScanning = true
        } label: {
          Label("Scan", systemImage: "camera")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .frame(width: Layout.canButtonSize, height: Layout.canButtonSize)
        .contentShape(Rectangle())
        .padding(Layout.canButtonOuterPadding)
      }
    }
  #endif

  @ViewBuilder internal var pin1Row: some View {
    CredentialSecretField(
      name: String(localized: "Basic Code (PIN 1)"),
      text: $pin1Entry,
      revealIdentifier: "pin1FieldReveal"
    ) {
      SecureField("Basic Code (PIN 1)", text: $pin1Entry)
        .font(.body)
        #if os(iOS)
          .keyboardType(.numberPad)
          .textInputAutocapitalization(.never)
        #endif
        .autocorrectionDisabled()
        .focused($isPin1FieldFocused)
        .accessibilityIdentifier("pin1Field")
        .onValueChange(of: pin1Entry) { typed in
          pin1Entry = LimitedDigits.pin1(typed)
        }
    }
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    internal var scannerSheet: some View {
      ScannerSheet(
        torchEnabled: $scannerTorchEnabled,
        isScanning: $isScanning
      ) { digits in
        cardAccessNumberEntry = digits
      }
    }
  #endif
}
