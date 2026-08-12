// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Observation

  /// Notices a card waiting to be taken into use, for the window that
  /// becomes its activation.
  ///
  /// The status window does no card I/O on its ordinary paths. The one
  /// probe here runs only after a present card has gone the identity
  /// row's settling time without publishing - past the driver's own
  /// mint and recovery window - and it opens one short session and
  /// closes it. An activated card that was merely slow answers
  /// "already active" and nothing changes; a factory-fresh card turns
  /// the window into its activation.
  @MainActor
  @Observable
  internal final class ActivationWatch {
    /// Whether the inserted card is still waiting to be taken into use.
    internal private(set) var awaitsActivation = false

    /// The model the activation form works through.
    internal let management = CardManagementModel()

    /// Follows one availability reading; cancelled by the next.
    ///
    /// `paused` stands the watch down while the window is asking for a
    /// card access number, for the same reason the drop target does:
    /// nothing may touch the card before the number has.
    internal func watch(
      availability: LoginIdentityModel.Availability,
      paused: Bool
    ) async {
      #if DEBUG
        if DebugActivationPreview.isEnabled() {
          awaitsActivation = true
          return
        }
      #endif
      guard availability == .cardWithoutIdentity, !paused else {
        awaitsActivation = false
        return
      }
      try? await Task.sleep(for: IdentityStateView.settleDelay)
      guard !Task.isCancelled else { return }
      // Through the model rather than a bare probe, so the same
      // reading also learns which PINs still wait - an interrupted
      // activation left one set, and the form asks only for the
      // other - and the counters the confirmation sheet shows.
      await management.refresh()
      awaitsActivation = management.offersActivation
    }
  }

#endif
