// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
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
          Section {
            LabeledContent("Requester") {
              Text(request.requester)
                .multilineTextAlignment(.trailing)
            }
          }

          if request.action == .documentSignature {
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .onAppear {
          pin2Focused = request.action == .documentSignature
        }
        .onDisappear {
          pin2 = ""
        }
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
        inbox.approve(request.id)
      case .documentSignature:
        inbox.approveDocumentSignature(request.id, pin2: pin2)
        pin2 = ""
      case .shareCardInformation:
        inbox.approve(request.id)
      }
    }

    private func deny() {
      pin2 = ""
      inbox.deny(request.id)
    }
  }
#endif
