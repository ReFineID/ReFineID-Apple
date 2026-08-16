// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import Foundation
  import Observation
  import SwiftUI

  /// One authenticated RAPP request awaiting the card holder's decision.
  ///
  /// The digest, PIN 1, CAN, keys, and wire frame are deliberately absent.
  /// SwiftUI receives only bounded display context and an action category.
  internal struct RappAuthorizationRequest: Identifiable, Sendable, Equatable {
    internal enum Action: Sendable, Equatable {
      case browserAuthentication
      case documentSignature
      case shareCardInformation
    }

    internal let id: String
    internal let requester: String
    internal let action: Action
  }

  internal enum RappAuthorizationDecision: Sendable, Equatable {
    case approved
    case approvedDocumentSignature(pin2: String)
    case denied
  }

  /// Main-actor rendezvous between the authenticated proxy and SwiftUI.
  ///
  /// There is no automatic approval, timeout, or queue. A second operation is
  /// denied while one is visible; expiry and disconnect arrive from the RAPP
  /// state machine and explicitly cancel the matching request.
  @MainActor @Observable
  internal final class RappAuthorizationInbox {
    internal static let shared = RappAuthorizationInbox()

    internal private(set) var request: RappAuthorizationRequest?
    private var continuation:
      CheckedContinuation<RappAuthorizationDecision, Never>?

    private init() {}

    internal func ask(
      _ offered: RappAuthorizationRequest
    ) async -> RappAuthorizationDecision {
      guard request == nil, continuation == nil else { return .denied }
      return await withCheckedContinuation { continuation in
        self.request = offered
        self.continuation = continuation
      }
    }

    internal func approve(_ requestID: String) {
      complete(requestID, with: .approved)
    }

    internal func approveDocumentSignature(
      _ requestID: String,
      pin2: String
    ) {
      guard Pin2(digits: pin2) != nil else { return }
      complete(requestID, with: .approvedDocumentSignature(pin2: pin2))
    }

    internal func deny(_ requestID: String) {
      complete(requestID, with: .denied)
    }

    /// Cancels only the operation the protocol named. A late cancellation
    /// cannot dismiss or decide a newer request.
    internal func cancel(_ requestID: String) {
      complete(requestID, with: .denied)
    }

    internal func cancelAll() {
      guard let request else { return }
      complete(request.id, with: .denied)
    }

    private func complete(
      _ requestID: String,
      with decision: RappAuthorizationDecision
    ) {
      guard request?.id == requestID, let continuation else { return }
      self.request = nil
      self.continuation = nil
      continuation.resume(returning: decision)
    }
  }

  /// System-modal holder authorization. It uses the app's shared secret-field
  /// control and native buttons; no parallel visual language is introduced.
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
                  .onChange(of: pin2) { _, typed in
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
