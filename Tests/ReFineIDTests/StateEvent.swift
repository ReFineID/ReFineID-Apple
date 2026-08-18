import Foundation

internal struct StateEvent: Hashable {
  internal let state: CardSetupStateMachine.State
  internal let event: CardSetupStateMachine.Event
}
