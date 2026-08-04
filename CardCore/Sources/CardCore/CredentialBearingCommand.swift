import Foundation

/// A credential-bearing command APDU, transmittable at most once.
///
/// Construction consumes the noncopyable PIN transmission(s); reading the
/// wire bytes consumes the command. The chain user entry -> PIN value ->
/// transmission -> this command -> one transport payload is linear and
/// compiler-enforced end to end: no step can be repeated, so a credential
/// can never be replayed after a timeout, reset, reconnect, or length
/// correction (Documentation/release-plan.md section 4.3).
public struct CredentialBearingCommand: ~Copyable {
  private let encoded: Data

  /// PIN1 VERIFY: `00 20 00 11 0C` + the entered digits right-padded
  /// with zero bytes to the stored length (FINEID S1 v4.2 §3.5.2,
  /// S4-1 v3.1).
  public static func verifyPin1(
    _ transmission: consuming Pin1Transmission
  ) -> Self {
    build(
      instruction: Iso7816Values.insVerify,
      parameter1: Iso7816Values.verifyModeP1,
      reference: FineidValues.pin1Reference,
      credentials: [transmission.store]
    )
  }

  /// PIN2 VERIFY: `00 20 00 82 0C` + the padded digits (S1 v4.2 §3.5.2).
  ///
  /// Verified state persists for the session until SELECT or reset;
  /// callers verify immediately before the one signature and never rely
  /// on it afterwards.
  public static func verifyPin2(
    _ transmission: consuming Pin2Transmission
  ) -> Self {
    build(
      instruction: Iso7816Values.insVerify,
      parameter1: Iso7816Values.verifyModeP1,
      reference: FineidValues.pin2Reference,
      credentials: [transmission.store]
    )
  }

  /// PIN1 CHANGE REFERENCE DATA: `00 24 00 11 18` + the current then
  /// the new digits, each right-padded to the stored length
  /// (S1 v4.2 §3.5.3).
  ///
  /// Success resets the retry counter to its maximum and clears the
  /// verified flag: the new PIN is set but not presented.
  public static func changePin1(
    current: consuming Pin1Transmission,
    new: consuming Pin1Transmission
  ) -> Self {
    build(
      instruction: Iso7816Values.insChangeReferenceData,
      parameter1: Iso7816Values.changeCurrentThenNewP1,
      reference: FineidValues.pin1Reference,
      credentials: [current.store, new.store]
    )
  }

  /// PIN2 CHANGE REFERENCE DATA: `00 24 00 82 18` + the current then
  /// the new digits, each right-padded (S1 v4.2 §3.5.3).
  ///
  /// Success resets the retry counter to its maximum and clears the
  /// verified flag: the new PIN is set but not presented.
  public static func changePin2(
    current: consuming Pin2Transmission,
    new: consuming Pin2Transmission
  ) -> Self {
    build(
      instruction: Iso7816Values.insChangeReferenceData,
      parameter1: Iso7816Values.changeCurrentThenNewP1,
      reference: FineidValues.pin2Reference,
      credentials: [current.store, new.store]
    )
  }

  /// PIN1 RESET RETRY COUNTER: `00 2C 00 11 18` + the PUK then the new
  /// PIN, each right-padded (S1 v4.2 §3.5.4).
  ///
  /// P1 `00` resets the target counter AND replaces its value; P2 names
  /// the target PIN - the PUK itself has no reference byte, it is the
  /// card's one unblocking key. A wrong PUK counts down the PUK's own
  /// retry counter, and exhausting it is terminal for the card.
  public static func unblockPin1(
    puk: consuming PukTransmission,
    new: consuming Pin1Transmission
  ) -> Self {
    build(
      instruction: Iso7816Values.insResetRetryCounter,
      parameter1: Iso7816Values.resetWithPukThenNewP1,
      reference: FineidValues.pin1Reference,
      credentials: [puk.store, new.store]
    )
  }

  /// PIN2 RESET RETRY COUNTER: `00 2C 00 82 18` + the PUK then the new
  /// PIN, each right-padded (S1 v4.2 §3.5.4).
  ///
  /// Same semantics as the PIN1 form: the target is named by P2, the
  /// PUK is implicit, and a wrong PUK spends the PUK's own counter.
  public static func unblockPin2(
    puk: consuming PukTransmission,
    new: consuming Pin2Transmission
  ) -> Self {
    build(
      instruction: Iso7816Values.insResetRetryCounter,
      parameter1: Iso7816Values.resetWithPukThenNewP1,
      reference: FineidValues.pin2Reference,
      credentials: [puk.store, new.store]
    )
  }

  /// Builds the single wire form: plain header, Lc covering the padded
  /// block(s), then each credential right-padded with the pad byte to
  /// the stored length (FINEID cards reject non-zero padding with
  /// `6A80`).
  ///
  /// Local copies are best-effort zeroized; the Data is owned by the
  /// command and consumed exactly once.
  private static func build(
    instruction: UInt8,
    parameter1: UInt8,
    reference: UInt8,
    credentials: [ZeroizingDigitStore]
  ) -> Self {
    var body: [UInt8] = [
      Iso7816Values.classInterindustry,
      instruction,
      parameter1,
      reference,
      UInt8(FineidValues.pinStoredLength * credentials.count),
    ]
    for credential in credentials {
      var block = credential.bytes
      while block.count < FineidValues.pinStoredLength {
        block.append(FineidValues.pinPadByte)
      }
      body.append(contentsOf: block)
      for index in block.indices {
        block[index] = 0
      }
    }
    let command = Self(encoded: Data(body))
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
