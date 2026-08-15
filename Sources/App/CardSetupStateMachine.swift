// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Pure transition engine for the iOS card-setup and card-operation flow.
///
/// `Documentation/card-setup-state-machine.scxml` is the canonical grammar.
/// Keep `transitions` structurally identical to that document; exhaustive tests
/// reject any difference between the two representations.
internal enum CardSetupStateMachine {
  internal enum State: String, CaseIterable, Sendable {
    case home
    case identityHome
    case classifyingBrowser
    case classifyingManagement
    case registeringBrowser
    case activation
    case pinManagementHome
    case pinManagementIdentity
    case documentSigningHome
    case documentSigningIdentity
  }

  internal enum Event: String, CaseIterable, Sendable {
    case identityLoaded = "identity.loaded"
    case identityForgotten = "identity.forgotten"
    case startBrowserClassification = "browser.classification.start"
    case startConfiguredBrowserRegistration = "browser.registration.start"
    case startManagementClassification = "management.classification.start"
    case openKnownActivation = "activation.open.known"
    case openVerifiedManagement = "management.open.verified"
    case openDocumentSigning = "signing.open"
    case classificationActivated = "classification.activated"
    case classificationRecoveryRequired = "classification.recovery-required"
    case classificationActivationRequired = "classification.activation-required"
    case classificationWrongCardAccessNumber = "classification.wrong-can"
    case classificationFailed = "classification.failed"
    case registrationSucceeded = "registration.succeeded"
    case registrationFailed = "registration.failed"
    case activationSucceeded = "activation.succeeded"
    case destinationDismissed = "destination.dismissed"
  }

  internal enum Destination: Hashable, Sendable {
    case activation
    case pinManagement
    case signDocuments
  }

  internal struct Transition: Hashable, Sendable {
    internal let source: State
    internal let event: Event
    internal let target: State

    internal init(source: State, event: Event, target: State) {
      self.source = source
      self.event = event
      self.target = target
    }
  }

  internal enum Reduction: Equatable, Sendable {
    case transitioned(to: State)
    case rejected
  }

  internal static let initialState = State.home

  /// Executable mirror of the canonical SCXML transition grammar.
  ///
  /// An absent `(state, event)` pair is an explicit rejection. There are no
  /// implicit self-transitions and no timing-based transitions.
  internal static let transitions: [Transition] = [
    .init(source: .home, event: .identityLoaded, target: .identityHome),
    .init(source: .home, event: .startBrowserClassification, target: .classifyingBrowser),
    .init(source: .home, event: .startConfiguredBrowserRegistration, target: .registeringBrowser),
    .init(source: .home, event: .startManagementClassification, target: .classifyingManagement),
    .init(source: .home, event: .openKnownActivation, target: .activation),
    .init(source: .home, event: .openVerifiedManagement, target: .pinManagementHome),
    .init(source: .home, event: .openDocumentSigning, target: .documentSigningHome),

    .init(source: .identityHome, event: .identityForgotten, target: .home),
    .init(source: .identityHome, event: .openVerifiedManagement, target: .pinManagementIdentity),
    .init(source: .identityHome, event: .openDocumentSigning, target: .documentSigningIdentity),

    .init(source: .classifyingBrowser, event: .classificationActivated, target: .registeringBrowser),
    .init(source: .classifyingBrowser, event: .classificationRecoveryRequired, target: .pinManagementHome),
    .init(source: .classifyingBrowser, event: .classificationActivationRequired, target: .activation),
    .init(source: .classifyingBrowser, event: .classificationWrongCardAccessNumber, target: .home),
    .init(source: .classifyingBrowser, event: .classificationFailed, target: .home),

    .init(source: .classifyingManagement, event: .classificationActivated, target: .pinManagementHome),
    .init(source: .classifyingManagement, event: .classificationRecoveryRequired, target: .pinManagementHome),
    .init(source: .classifyingManagement, event: .classificationActivationRequired, target: .activation),
    .init(source: .classifyingManagement, event: .classificationWrongCardAccessNumber, target: .home),
    .init(source: .classifyingManagement, event: .classificationFailed, target: .home),

    .init(source: .registeringBrowser, event: .registrationSucceeded, target: .identityHome),
    .init(source: .registeringBrowser, event: .registrationFailed, target: .home),

    .init(source: .activation, event: .activationSucceeded, target: .home),
    .init(source: .activation, event: .destinationDismissed, target: .home),

    .init(source: .pinManagementHome, event: .destinationDismissed, target: .home),
    .init(source: .pinManagementIdentity, event: .destinationDismissed, target: .identityHome),
    .init(source: .documentSigningHome, event: .destinationDismissed, target: .home),
    .init(source: .documentSigningIdentity, event: .destinationDismissed, target: .identityHome),
  ]

  internal static func reduce(state: State, event: Event) -> Reduction {
    let matches = transitions.lazy.filter { $0.source == state && $0.event == event }
    guard let transition = matches.first else {
      return .rejected
    }
    precondition(matches.dropFirst().isEmpty, "Ambiguous card-setup transition")
    return .transitioned(to: transition.target)
  }
}

extension CardSetupStateMachine.State {
  internal var destination: CardSetupStateMachine.Destination? {
    switch self {
    case .activation:
      .activation
    case .pinManagementHome, .pinManagementIdentity:
      .pinManagement
    case .documentSigningHome, .documentSigningIdentity:
      .signDocuments
    case .home, .identityHome, .classifyingBrowser, .classifyingManagement, .registeringBrowser:
      nil
    }
  }
}
