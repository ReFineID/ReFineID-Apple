// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation
  import SwiftUI

  /// Main-actor rendezvous between the authenticated proxy and SwiftUI.
  ///
  /// There is no automatic approval, timeout, or queue. A second operation is
  /// denied while one is visible; expiry and disconnect arrive from the RAPP
  /// state machine and explicitly cancel the matching request.
  @MainActor
  internal final class RappAuthorizationInbox: ObservableObject {
    internal static let shared = RappAuthorizationInbox()

    @Published internal private(set) var request: RappAuthorizationRequest?
    private var continuation: CheckedContinuation<RappAuthorizationDecision, Never>?

    private init() {
      // singleton
    }

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

    internal func approveBrowserAuthentication(
      _ requestID: String,
      pin1: String
    ) {
      guard Pin1(digits: pin1) != nil else { return }
      complete(requestID, with: .approvedBrowserAuthentication(pin1: pin1))
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

    /// Cancels only the operation the protocol named.
    ///
    /// A late cancellation cannot dismiss or decide a newer request.
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
#endif
