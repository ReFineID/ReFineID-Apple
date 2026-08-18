import Foundation

internal struct ParsedGrammar {
  internal let initialState: CardSetupStateMachine.State
  internal let states: Set<CardSetupStateMachine.State>
  internal let transitions: [CardSetupStateMachine.Transition]
}
