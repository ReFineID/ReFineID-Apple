// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_REMOTE_CARD
  import CardCore
  import SwiftUI

  /// System-modal holder authorization.
  ///
  /// It uses the app's shared secret-field control and native buttons;
  /// no parallel visual language is introduced.
  internal struct RappAuthorizationView: View {
    internal let request: RappAuthorizationRequest
    internal let inbox: RappAuthorizationInbox

    @State private var pin2 = ""
    @FocusState private var pin2Focused: Bool

    private var title: LocalizedStringKey {
      switch request.action {
      case .browserAuthentication:
        "Browser authentication"

      case .documentSignature:
        "Document signature"

      case .shareCardInformation:
        "Share card information"
      }
    }

    internal var body: some View {
      NavigationStack {
        Form {
          requesterSection
          if request.action == .documentSignature {
            signPin2Section
          }
          actionsSection
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .onAppear {
          if request.action == .documentSignature {
            pin2Focused = true
          }
        }
        .onDisappear {
          pin2 = ""
        }
      }
    }

    private var requesterSection: some View {
      Section {
        LabeledContent("Requester") {
          Text(request.requester)
            .multilineTextAlignment(.trailing)
        }
      }
    }

    private var signPin2Section: some View {
      Section("Signature authorization") {
        CredentialSecretField(
          name: String(localized: "Signature (PIN 2)"),
          text: $pin2,
          revealIdentifier: "rappPin2Reveal"
        ) {
          SecureField("Signature (PIN 2)", text: $pin2)
            .keyboardType(.numberPad)
            .textContentType(.none)
            .onValueChange(of: pin2) { typed in
              pin2 = LimitedDigits.pin(typed)
            }
            .focused($pin2Focused)
            .accessibilityIdentifier("rappPin2")
        }
      }
    }

    private var actionsSection: some View {
      Section {
        Button {
          approve()
        } label: {
          Text("Approve")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canApprove)
        .accessibilityIdentifier("rappApprove")

        Button(role: .destructive) {
          deny()
        } label: {
          Text("Deny")
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("rappDeny")
      }
    }

    private var canApprove: Bool {
      switch request.action {
      case .browserAuthentication:
        true

      case .documentSignature:
        Pin2(digits: pin2) != nil

      case .shareCardInformation:
        true
      }
    }

    private func approve() {
      switch request.action {
      case .browserAuthentication:
        inbox.approve(request.requestID)

      case .documentSignature:
        inbox.approveDocumentSignature(request.requestID, pin2: pin2)
        pin2 = ""

      case .shareCardInformation:
        inbox.approve(request.requestID)
      }
    }

    private func deny() {
      pin2 = ""
      inbox.deny(request.requestID)
    }
  }
#endif
