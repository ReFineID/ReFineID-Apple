import Foundation

/// A credential-bearing command APDU, transmittable at most once.
///
/// Construction consumes the noncopyable PIN transmission; reading the
/// wire bytes consumes the command. The chain user entry ->  `Pin1` ->
/// `Pin1Transmission` -> this command -> one transport payload is linear
/// and compiler-enforced end to end: no step can be repeated, so a
/// credential can never be replayed after a timeout, reset, reconnect,
/// or length correction (Documentation/release-plan.md section 4.3).
public struct CredentialBearingCommand: ~Copyable {
  private let encoded: Data

  /// PIN1 VERIFY: `00 20 00 11 0C` + the entered digits right-padded
  /// with zero bytes to the stored length (FINEID S1 v4.2 §3.5.2,
  /// S4-1 v3.1).
  public static func verifyPin1(
    _ transmission: consuming Pin1Transmission
  ) -> Self {
    var body: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insVerify,
      Iso7816Values.verifyModeP1,
      FineidValues.pin1Reference,
      UInt8(FineidValues.pinStoredLength),
    ]
    var block = transmission.store.bytes
    while block.count < FineidValues.pinStoredLength {
      block.append(FineidValues.pinPadByte)
    }
    body.append(contentsOf: block)
    let command = Self(encoded: Data(body))
    // Best-effort zeroization of the local copies; the Data above is
    // owned by the command and consumed exactly once.
    for index in block.indices {
      block[index] = 0
    }
    for index in body.indices {
      body[index] = 0
    }
    return command
  }

  /// Consumes the command into the bytes the transport sends.
  ///
  /// After this call the command no longer exists; retransmission
  /// requires a fresh user entry by construction.
  public consuming func intoTransportPayload() -> Data {
    encoded
  }
}
