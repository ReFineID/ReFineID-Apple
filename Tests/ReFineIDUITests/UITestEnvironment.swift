// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a run was told from outside, and nothing that could have been
/// written down here.
///
/// A card access number and a PIN1 belong to a holder, not to a
/// repository. They are read from the test runner's environment on every
/// run, never defaulted, never printed, and never attached to a result.
/// The most a failure is allowed to say about them is how many digits
/// arrived, which is what catches a shell that ate a leading zero.
///
/// `xcodebuild` copies every variable in ITS OWN environment whose name
/// starts with `TEST_RUNNER_` into the runner process, with the prefix
/// stripped, so `TEST_RUNNER_REFINEID_TEST_CAN` arrives here as
/// `REFINEID_TEST_CAN`. The prefix is required: the runner is a separate
/// process the system launches, and a plain `REFINEID_TEST_CAN` never
/// reaches it.
///
/// The variable must be set on the `xcodebuild` invocation itself --
/// `TEST_RUNNER_REFINEID_TEST_CAN=... xcodebuild test ...` -- and NOT
/// appended after the arguments. Measured: a trailing
/// `TEST_RUNNER_REFINEID_TEST_CAN=...` is parsed as a build setting,
/// xcodebuild accepts it silently, and nothing arrives here at all.
internal enum UITestEnvironment {
  /// Variable holding the six digits printed on the card.
  internal static let cardAccessNumberVariable = "REFINEID_TEST_CAN"

  /// Variable holding PIN1.
  internal static let pin1Variable = "REFINEID_TEST_PIN1"

  /// Variable holding the site the login test drives.
  internal static let targetSiteVariable = "REFINEID_SAFARI_URL"

  /// Variable holding the text that proves the login landed.
  internal static let successMarkerVariable = "REFINEID_SAFARI_SUCCESS"

  /// The card access number, or nil when the run was not given one.
  internal static var cardAccessNumber: String? {
    Self.digits(Self.cardAccessNumberVariable)
  }

  /// PIN1, or nil when the run was not given one.
  internal static var pin1: String? {
    Self.digits(Self.pin1Variable)
  }

  /// The site the login test drives.
  ///
  /// The default REQUIRES client authentication, and that is the whole
  /// point of it. An optional-auth server lets Safari finish cert-less
  /// with a 403 and never asks for a certificate at all, so a run against
  /// one proves nothing whichever way it goes. `card.refineid.fi` is
  /// optional-auth; this default and `suomi.fi` are not.
  internal static var targetSite: String {
    Self.value(Self.targetSiteVariable) ?? "admin.iki.fi/perlhst/admin/?login=thoron"
  }

  /// The text on the signed-in page that says the login landed.
  ///
  /// Per-site, so it travels with the site rather than being guessed.
  internal static var successMarker: String {
    Self.value(Self.successMarkerVariable) ?? "thoron"
  }

  /// One variable, with empty treated as absent.
  ///
  /// An empty variable is what a shell leaves behind when the value it was
  /// meant to carry was never set, and treating it as present turns a
  /// missing secret into a mystifying failure much later.
  private static func value(_ name: String) -> String? {
    guard let raw = ProcessInfo.processInfo.environment[name], !raw.isEmpty else {
      return nil
    }
    return raw
  }

  /// One variable that has to be digits, or nothing.
  ///
  /// Refusing non-digits here means a stray quote or a trailing newline
  /// fails as "not given" rather than being typed into the card setup
  /// screen and rejected there for a reason nobody can see.
  private static func digits(_ name: String) -> String? {
    guard let raw = Self.value(name), raw.allSatisfy(\.isNumber) else {
      return nil
    }
    return raw
  }
}
