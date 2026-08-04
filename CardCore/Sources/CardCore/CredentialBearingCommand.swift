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

  /// VERIFY against the PIN1 reference (FINEID S1 v4.2 §3.5.2,
  /// S4-1 v3.1).
  ///
  /// The data field is one padded credential block; `build` names the
  /// layout.
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

  /// VERIFY against the PIN2 reference (S1 v4.2 §3.5.2).
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

  /// CHANGE REFERENCE DATA against the PIN1 reference: the current
  /// credential block, then the new (S1 v4.2 §3.5.3).
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

  /// CHANGE REFERENCE DATA against the PIN2 reference: the current
  /// credential block, then the new (S1 v4.2 §3.5.3).
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

  /// RESET RETRY COUNTER against the PIN1 reference: the PUK block,
  /// then the new credential block (S1 v4.2 §3.5.4).
  ///
  /// The reset-and-replace mode both resets the target's counter and
  /// sets its new value. The command's reference names the target PIN;
  /// the PUK itself has none, being the card's one unblocking key. A
  /// wrong PUK counts down the PUK's own retry counter, and exhausting
  /// it is terminal for the card.
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

  /// RESET RETRY COUNTER against the PIN2 reference: the PUK block,
  /// then the new credential block (S1 v4.2 §3.5.4).
  ///
  /// Same semantics as the PIN1 form: the reference names the target,
  /// the PUK is implicit, and a wrong PUK spends the PUK's own
  /// counter.
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

  /// Builds the one wire form every credential command shares.
  ///
  /// Interindustry class, the instruction, its mode parameter, the
  /// credential reference, a length byte covering the blocks, then each
  /// credential right-padded with the pad byte to the stored length -
  /// FINEID cards reject any other padding. The named constants in
  /// `Iso7816Values` and `FineidValues` are the single home of the
  /// actual bytes; the tests hold the assembled vectors.
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
