// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  /// One cable-side debug mode, named by the flag that selects it.
  ///
  /// The vocabulary only: what each mode does lives in
  /// ``DebugLaunchModes``, which dispatches them, and in
  /// ``DebugSceneRunnerView``, which hosts the ones that need a window.
  /// Keeping the names here means a new mode is added in one place and
  /// cannot be spelled two ways.
  ///
  /// DEBUG only. A release build knows none of these flags.
  internal enum DebugLaunchMode: String, CaseIterable, Sendable {
    /// Read the factory-activation signals over NFC without changing the card.
    case activationProbe = "--activation-probe"

    /// Sign through the token extension exactly as Safari does.
    case ctkSignProbe = "--ctk-sign-probe"

    /// Print everything the status screen shows, as text.
    case diagnostics = "--diagnostics"

    /// Drop the stored card access number, wherever it is kept.
    case forgetCan = "--forget-can"

    /// Try one connection to an address on this network and report it.
    ///
    /// Local network access is refused silently, so an absence of peers
    /// says nothing. A connection reports a state.
    case localNetworkProbe = "--local-network-probe"

    /// Changes and restores both PINs over a named physical transport.
    case managementProbe = "--management-probe"

    /// Runs one PACE handshake over an attached reader and times it.
    case paceCheck = "--pace-check"

    /// Run the card priming flow with no interface.
    case prime = "--prime"

    /// Ask the paired device for its authentication certificate over the
    /// relay, and report what came back.
    ///
    /// The answer comes from the peer's stored prime, so this drives the
    /// whole relay -- pairing, session, request, answer -- without a card
    /// being presented to anything.
    case remoteIdentityProbe = "--remote-identity-probe"

    /// Return this device to a known zero: no token, no prime, no window,
    /// no trace.
    case resetCardState = "--reset-card-state"

    /// Choose the pairing whose identifier starts with the given prefix.
    ///
    /// A device paired more than once holds several, and only the peer
    /// knows which of them it shares.
    case selectPair = "--select-pair"

    /// Store a card access number given on the command line.
    case setCan = "--set-can"

    /// Store a PIN1 given on the command line.
    case setPin1 = "--set-pin1"

    /// Sign a PDF at the archival level, with PIN2 read from the
    /// environment, and report what each step produced.
    case signDocument = "--sign-document"

    /// Sign against the card directly, with a PIN1 given on the command
    /// line, and verify the result.
    case signProbe = "--sign-probe"

    /// Read the card and build the keychain items a token would publish.
    case tokenPublishProbe = "--token-publish-probe"

    /// Print the trace the token extension left behind.
    case trace = "--trace"

    /// Whether this mode has to wait for a live scene.
    ///
    /// Two of them cannot run the way the rest do. CoreNFC will not open
    /// a slot for a process with no foreground window, and the system PIN
    /// sheet the extension raises needs the app's run loop to be running
    /// to appear at all.
    /// Every other mode only reads or writes this device's own state, or
    /// drives a reader that needs no interface, and is finished before a
    /// window would have existed.
    internal var needsScene: Bool {
      switch self {
      case .diagnostics, .forgetCan, .localNetworkProbe, .paceCheck,
        .resetCardState, .selectPair, .setCan, .setPin1, .signDocument,
        .signProbe, .tokenPublishProbe, .trace:
        false
      case .activationProbe, .ctkSignProbe, .managementProbe, .prime,
        .remoteIdentityProbe:
        // MultipeerConnectivity browses only for an app that has a window.
        // A probe that runs before one exists finds the peer's name in the
        // service records and is never handed the peer itself.
        true
      }
    }

    /// Whether the flag is followed by a value on the command line.
    ///
    /// Three modes take one, all of them digits, and the value is read
    /// from the command line at each launch and never committed anywhere.
    internal var takesValue: Bool {
      switch self {
      case .activationProbe, .ctkSignProbe, .diagnostics, .forgetCan, .paceCheck, .prime,
        .remoteIdentityProbe, .resetCardState, .tokenPublishProbe, .trace:
        false
      case .localNetworkProbe:
        true
      case .managementProbe, .selectPair, .setCan, .setPin1, .signDocument, .signProbe:
        true
      }
    }
  }

#endif
