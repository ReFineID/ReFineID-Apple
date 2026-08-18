// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension PairingState {
  /// The pairing rule that fires, or nil when none does.
  internal static func transition(
    from state: Self,
    on event: PairingEvent,
    role: EndpointRole,
    guards: RappGuards = .allSatisfied
  ) -> RappTransition<Self>? {
    guard case .fire(let transition) = outcome(from: state, on: event, role: role, guards: guards)
    else { return nil }
    return transition
  }

  internal static func outcome(
    from state: Self,
    on event: PairingEvent,
    role: EndpointRole,
    guards: RappGuards = .allSatisfied
  ) -> RappTransitionOutcome<Self> {
    rappResolve(RappModelTables.pairing, from: state, on: event, role: role, guards: guards)
  }
}
