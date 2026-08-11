// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

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
    /// Sign through the token extension exactly as Safari does.
    case ctkSignProbe = "--ctk-sign-probe"

    /// Print everything the status screen shows, as text.
    case diagnostics = "--diagnostics"

    /// Drop the stored card access number, wherever it is kept.
    case forgetCan = "--forget-can"

    /// Runs one PACE handshake over an attached reader and times it.
    case paceCheck = "--pace-check"

    /// Run the card priming flow with no interface.
    case prime = "--prime"

    /// Return this device to a known zero: no token, no prime, no window,
    /// no trace.
    case resetCardState = "--reset-card-state"

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
      case .diagnostics, .forgetCan, .paceCheck, .resetCardState, .setCan,
        .setPin1, .signDocument, .signProbe, .tokenPublishProbe, .trace:
        false
      case .ctkSignProbe, .prime:
        true
      }
    }

    /// Whether the flag is followed by a value on the command line.
    ///
    /// Three modes take one, all of them digits, and the value is read
    /// from the command line at each launch and never committed anywhere.
    internal var takesValue: Bool {
      switch self {
      case .ctkSignProbe, .diagnostics, .forgetCan, .paceCheck, .prime,
        .resetCardState, .tokenPublishProbe, .trace:
        false
      case .setCan, .setPin1, .signDocument, .signProbe:
        true
      }
    }
  }

#endif
