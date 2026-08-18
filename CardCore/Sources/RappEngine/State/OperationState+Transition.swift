// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension OperationState {
  /// The operation rule that fires, or nil when none does.
  internal static func transition(
    from state: Self,
    on event: OperationEvent,
    role: EndpointRole,
    guards: RappGuards = .allSatisfied
  ) -> RappTransition<Self>? {
    guard case .fire(let transition) = outcome(from: state, on: event, role: role, guards: guards)
    else { return nil }
    return transition
  }

  internal static func outcome(
    from state: Self,
    on event: OperationEvent,
    role: EndpointRole,
    guards: RappGuards = .allSatisfied
  ) -> RappTransitionOutcome<Self> {
    rappResolve(RappModelTables.operation, from: state, on: event, role: role, guards: guards)
  }
}
