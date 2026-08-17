// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest

@testable import ReFineID

final class CardSetupStateMachineTests: XCTestCase {
  private struct ParsedGrammar {
    let initialState: CardSetupStateMachine.State
    let states: Set<CardSetupStateMachine.State>
    let transitions: [CardSetupStateMachine.Transition]
  }

  private struct StateEvent: Hashable {
    let state: CardSetupStateMachine.State
    let event: CardSetupStateMachine.Event
  }

  func testSwiftTransitionTableExactlyMatchesCanonicalSCXML() throws {
    let grammar = try loadGrammar()

    XCTAssertEqual(grammar.initialState, CardSetupStateMachine.initialState)
    XCTAssertEqual(grammar.states, Set(CardSetupStateMachine.State.allCases))
    XCTAssertEqual(
      grammar.transitions.count,
      Set(grammar.transitions).count,
      "SCXML contains duplicate transitions"
    )
    XCTAssertEqual(
      CardSetupStateMachine.transitions.count,
      Set(CardSetupStateMachine.transitions).count,
      "Swift contains duplicate transitions"
    )
    XCTAssertEqual(Set(grammar.transitions), Set(CardSetupStateMachine.transitions))
  }

  func testEveryStateEventPairMatchesGrammarTransitionOrRejection() throws {
    let grammar = try loadGrammar()
    let transitions = Dictionary(grouping: grammar.transitions) {
      StateEvent(state: $0.source, event: $0.event)
    }

    for state in CardSetupStateMachine.State.allCases {
      for event in CardSetupStateMachine.Event.allCases {
        let expected = transitions[StateEvent(state: state, event: event), default: []]
        XCTAssertLessThanOrEqual(expected.count, 1, "Grammar is ambiguous for \(state), \(event)")

        switch (expected.first, CardSetupStateMachine.reduce(state: state, event: event)) {
        case (.some(let transition), .transitioned(let target)):
          XCTAssertEqual(target, transition.target, "Mismatch for \(state), \(event)")
        case (.none, .rejected):
          break
        default:
          XCTFail("Grammar/reducer disagreement for \(state), \(event)")
        }
      }
    }
  }

  func testEveryDeclaredStateIsReachableFromInitialState() {
    var reached: Set<CardSetupStateMachine.State> = [CardSetupStateMachine.initialState]
    var frontier = Array(reached)

    while let source = frontier.popLast() {
      for transition in CardSetupStateMachine.transitions where transition.source == source {
        if reached.insert(transition.target).inserted {
          frontier.append(transition.target)
        }
      }
    }

    XCTAssertEqual(reached, Set(CardSetupStateMachine.State.allCases))
  }

  func testClassificationStatesHandleEveryCardOutcome() {
    let outcomes: Set<CardSetupStateMachine.Event> = [
      .classificationActivated,
      .classificationRecoveryRequired,
      .classificationActivationRequired,
      .classificationWrongCardAccessNumber,
      .classificationFailed,
    ]

    for state in [
      CardSetupStateMachine.State.classifyingBrowser,
      .classifyingManagementHome,
      .classifyingManagementIdentity,
    ] {
      let handled = Set(
        CardSetupStateMachine.transitions
          .filter { $0.source == state }
          .map(\.event)
      )
      XCTAssertEqual(handled, outcomes, "Incomplete classification outcomes for \(state)")
    }
  }

  func testCardOutcomeRoutesRespectPurpose() {
    assertTransition(.classifyingBrowser, .classificationActivated, .registeringBrowser)
    assertTransition(.classifyingManagementHome, .classificationActivated, .pinManagementHome)
    assertTransition(
      .classifyingManagementIdentity, .classificationActivated, .pinManagementIdentity)
    assertTransition(.classifyingBrowser, .classificationRecoveryRequired, .pinManagementHome)
    assertTransition(
      .classifyingManagementHome, .classificationRecoveryRequired, .pinManagementHome)
    assertTransition(
      .classifyingManagementIdentity, .classificationRecoveryRequired, .pinManagementIdentity)
    assertTransition(.classifyingBrowser, .classificationActivationRequired, .activationHome)
    assertTransition(.classifyingManagementHome, .classificationActivationRequired, .activationHome)
    assertTransition(
      .classifyingManagementIdentity, .classificationActivationRequired, .activationIdentity)
  }

  func testDestinationDismissalPreservesIdentityOrigin() {
    assertTransition(.activationHome, .destinationDismissed, .home)
    assertTransition(.activationIdentity, .destinationDismissed, .identityHome)
    assertTransition(.pinManagementHome, .destinationDismissed, .home)
    assertTransition(.pinManagementIdentity, .destinationDismissed, .identityHome)
    assertTransition(.documentSigningHome, .destinationDismissed, .home)
    assertTransition(.documentSigningIdentity, .destinationDismissed, .identityHome)
  }

  func testDestinationProjectionIsCompleteAndUnambiguous() {
    let expected: [CardSetupStateMachine.State: CardSetupStateMachine.Destination] = [
      .activationHome: .activation,
      .activationIdentity: .activation,
      .pinManagementHome: .pinManagement,
      .pinManagementIdentity: .pinManagement,
      .documentSigningHome: .signDocuments,
      .documentSigningIdentity: .signDocuments,
    ]

    for state in CardSetupStateMachine.State.allCases {
      XCTAssertEqual(state.destination, expected[state], "Unexpected destination for \(state)")
    }
  }

  func testIdentityOriginSurvivesEveryManagementClassificationFailure() {
    assertTransition(
      .classifyingManagementIdentity,
      .classificationWrongCardAccessNumber,
      .identityHome)
    assertTransition(
      .classifyingManagementIdentity,
      .classificationFailed,
      .identityHome)
  }

  private func assertTransition(
    _ source: CardSetupStateMachine.State,
    _ event: CardSetupStateMachine.Event,
    _ target: CardSetupStateMachine.State,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      CardSetupStateMachine.reduce(state: source, event: event),
      .transitioned(to: target),
      file: file,
      line: line
    )
  }

  private func loadGrammar() throws -> ParsedGrammar {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url =
      repositoryRoot
      .appendingPathComponent("Documentation")
      .appendingPathComponent("card-setup-state-machine.scxml")
    let parser = XMLParser(contentsOf: url)
    let delegate = GrammarParserDelegate()
    parser?.delegate = delegate

    XCTAssertTrue(
      parser?.parse() == true, parser?.parserError?.localizedDescription ?? "SCXML parse failed")
    XCTAssertTrue(delegate.errors.isEmpty, delegate.errors.joined(separator: "\n"))

    return ParsedGrammar(
      initialState: try XCTUnwrap(delegate.initialState),
      states: delegate.states,
      transitions: delegate.transitions
    )
  }
}

private final class GrammarParserDelegate: NSObject, XMLParserDelegate {
  var initialState: CardSetupStateMachine.State?
  var states: Set<CardSetupStateMachine.State> = []
  var transitions: [CardSetupStateMachine.Transition] = []
  var errors: [String] = []

  private var currentState: CardSetupStateMachine.State?

  func parser(
    _: XMLParser,
    didStartElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch elementName {
    case "scxml":
      guard let rawInitial = attributeDict["initial"],
        let initial = CardSetupStateMachine.State(rawValue: rawInitial)
      else {
        errors.append("Unknown or missing SCXML initial state")
        return
      }
      initialState = initial

    case "state":
      guard let rawState = attributeDict["id"],
        let state = CardSetupStateMachine.State(rawValue: rawState)
      else {
        errors.append("Unknown or missing SCXML state id")
        return
      }
      if !states.insert(state).inserted {
        errors.append("Duplicate SCXML state id \(rawState)")
      }
      currentState = state

    case "transition":
      guard let source = currentState,
        let rawEvent = attributeDict["event"],
        let event = CardSetupStateMachine.Event(rawValue: rawEvent),
        let rawTarget = attributeDict["target"],
        let target = CardSetupStateMachine.State(rawValue: rawTarget)
      else {
        errors.append("Unknown or incomplete transition \(attributeDict)")
        return
      }
      transitions.append(.init(source: source, event: event, target: target))

    default:
      break
    }
  }

  func parser(
    _: XMLParser,
    didEndElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?
  ) {
    if elementName == "state" {
      currentState = nil
    }
  }
}
