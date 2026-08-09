import CryptoTokenKit
import Foundation

/// The PIN2 prompt for a qualified-signature operation.
///
/// The same capture-then-verify shape as `Pin1AuthOperation`, against
/// the qualified key's own constraint. What it deliberately does not
/// share is any memory: PIN2 is never cached, so every qualified
/// signature is one prompt, one VERIFY, one signature.
internal final class Pin2AuthOperation: TKTokenPasswordAuthOperation {
  /// The constraint marker the published qualified key carries.
  ///
  /// Distinct from the PIN1 constraint so `beginAuthFor` knows which
  /// credential the system is collecting, and so no PIN1 flow can ever
  /// satisfy a qualified signature.
  internal static let signDataConstraint = "fi.refineid.pin2.signData"

  private let capture: (String) -> Void

  internal init(capture: @escaping (String) -> Void) {
    self.capture = capture
    super.init()
  }

  // CryptoTokenKit never archives a live auth operation, so decoding one
  // is unreachable; the initializer exists only for NSSecureCoding.
  internal required init?(coder: NSCoder) {
    self.capture = { _ in
      // Unreachable: a decoded operation is never finished.
    }
    super.init(coder: coder)
  }

  override internal func finish() throws {
    guard let pin = password, !pin.isEmpty else {
      TokenLog.error("PIN2 sheet finished with nothing entered")
      throw TKError(.authenticationFailed)
    }
    TokenLog.info("PIN2 sheet finished with \(pin.count) digits")
    capture(pin)
  }
}
