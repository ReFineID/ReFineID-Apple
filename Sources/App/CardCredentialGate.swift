import Foundation
import LocalAuthentication

/// Face ID (or the device passcode) in front of the card's stored
/// secrets.
///
/// The gate lives here, in the app, because this is the only place a
/// person is present to answer it: the token extension reads the same
/// secrets while signing a request made in Safari and has no interface of
/// its own, so a biometric access control on the keychain items
/// themselves would stall those logins on a prompt nobody can see. Every
/// path that shows, changes, or clears a secret goes through this type.
///
/// Biometry falls back to the passcode rather than requiring a face: a
/// holder whose Face ID fails at a card reader still needs a way in, and
/// the passcode is the same secret that protects the keychain item
/// underneath.
internal enum CardCredentialGate {
  /// Why an attempt did not result in access.
  internal enum Refusal: Error {
    /// The holder cancelled, or authentication failed.
    case denied

    /// The device offers neither biometry nor a passcode.
    case unavailable
  }

  /// Runs `reason` past the holder, returning only if they authenticate.
  ///
  /// `reason` is shown verbatim in the system prompt, so it should say
  /// what is about to happen in the holder's terms.
  internal static func authenticate(reason: String) async throws {
    let context = LAContext()
    context.localizedCancelTitle = String(localized: "Cancel")
    var availability: NSError?
    guard
      context.canEvaluatePolicy(
        .deviceOwnerAuthentication, error: &availability)
    else {
      throw Refusal.unavailable
    }
    do {
      let allowed = try await context.evaluatePolicy(
        .deviceOwnerAuthentication, localizedReason: reason)
      guard allowed else { throw Refusal.denied }
    } catch is Refusal {
      throw Refusal.denied
    } catch {
      throw Refusal.denied
    }
  }
}
