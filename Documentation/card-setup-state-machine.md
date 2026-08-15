# Card setup state machine

`card-setup-state-machine.scxml` is the canonical, machine-readable grammar for
the iOS card-setup and card-operation flow. `CardSetupStateMachine.swift` is its
pure executable mirror. The UI sends events to that reducer and derives
navigation from the resulting state.

## Contract

- A transition happens only in response to an explicit event.
- An event absent from the current SCXML state is rejected.
- There are no implicit self-transitions.
- There are no delay- or timer-driven transitions.
- Browser setup and PIN-management classification remain distinct until the
  card result is known.
- An unactivated or partially activated card routes to activation.
- A card requiring retry recovery routes to PIN management.
- Wrong CAN and transport/classification failure return to the unregistered
  home state without publishing an identity.
- Dismissing a destination restores the correct registered or unregistered
  origin.

## Change control

Every behavior change must update all of these artifacts in one change:

1. The SCXML grammar.
2. The Swift transition table.
3. Model tests and, when visible behavior changes, UI scenarios.

The model test parses the SCXML and compares its complete transition relation
with Swift. It then enumerates every `State x Event` pair, verifies the same
transition or rejection in both representations, checks reachability, rejects
ambiguous transitions, and checks routing invariants. This makes an unmodeled
Swift transition and a stale grammar test failure rather than documentation
drift.

## Scope

The grammar owns application-level setup and destination routing. Lower-level
card protocols, PIN retry policy, activation APDUs, and NFC transport lifetimes
remain separate state machines and feed their verified outcomes into this one
as events.

## Method

The format follows W3C SCXML 1.0. The separation between the declarative
transition relation and the pure reducer follows statechart and model-based
testing practice described in the project references.
