import Foundation

/// A read-only, idempotent command APDU.
///
/// Every command constructible here is safe to retransmit: it carries no
/// credential and has no side effect on retry counters. Credential-
/// bearing commands are a different, noncopyable type
/// (`CredentialBearingCommand`), so the safety class of every command is
/// part of its type (Documentation/release-plan.md section 5).
public struct CommandApdu: Equatable, Sendable {
  /// The wire bytes handed to the transport.
  public let encoded: Data

  /// SELECT by application identifier, first occurrence, no FCI
  /// requested: `00 A4 04 0C Lc AID` (FINEID S1 v4.2; ISO 7816-4
  /// §11.1.1).
  public static func selectApplication(_ aid: ApplicationIdentifier) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insSelect,
      Iso7816Values.selectByAidP1,
      Iso7816Values.selectByAidNoFciP2,
    ]
    bytes.append(UInt8(aid.bytes.count))
    bytes.append(contentsOf: aid.bytes)
    return Self(encoded: Data(bytes))
  }

  /// SELECT an elementary file under the current DF (S1 v4.2 §3.2.2).
  ///
  /// Wire shape `00 A4 02 0C 02 FID`, no response data requested.
  /// Selecting the eID application first makes its DF current; this
  /// then selects EFs beneath it without any FCI parsing.
  public static func selectElementaryFile(_ file: FileIdentifier) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insSelect,
      Iso7816Values.selectEfUnderCurrentDfP1,
      Iso7816Values.selectNoResponseP2,
    ]
    bytes.append(UInt8(file.bytes.count))
    bytes.append(contentsOf: file.bytes)
    return Self(encoded: Data(bytes))
  }

  /// SELECT a file by identifier with an explicit P1, no response data:
  /// `00 A4 <p1> 0C 02 FID` (ISO 7816-4 §11.1.1).
  ///
  /// Card generations accept different P1 encodings for the master file
  /// and child directories; `CardOperations` tries the proven variants
  /// in order (ported from the reference implementation), so the P1 is
  /// a named value chosen by the caller, never a bare literal.
  public static func selectFile(
    _ file: FileIdentifier,
    selectionP1: UInt8
  ) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insSelect,
      selectionP1,
      Iso7816Values.selectNoResponseP2,
    ]
    bytes.append(UInt8(file.bytes.count))
    bytes.append(contentsOf: file.bytes)
    return Self(encoded: Data(bytes))
  }

  /// READ BINARY from the current EF: `00 B0 P1 P2 Le`
  /// (ISO 7816-4 §11.2.2).
  public static func readBinary(
    offset: ReadOffset,
    expectedLength: ExpectedResponseLength
  ) -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insReadBinary,
        offset.p1Byte,
        offset.p2Byte,
        expectedLength.encodedByte,
      ])
    )
  }

  /// The side-effect-free retry-counter probe (FINEID S1 v4.2 §3.5.1.1).
  ///
  /// VERIFY with `Lc=00` and no data: the card answers `63Cx` with the
  /// remaining attempts in the counter nibble and no attempt is
  /// consumed. This is the reading the retry floor requires immediately
  /// before every PIN-bearing command.
  public static func readRetryCounter(role: CredentialRole) -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insVerify,
        Iso7816Values.verifyModeP1,
        FineidValues.reference(for: role),
        0,
      ])
    )
  }

  /// GET RESPONSE for a T=0 `61xx` continuation (ISO 7816-4 §11.7.1).
  ///
  /// `00 C0 00 00 Le` where Le is the announced count; a count of zero
  /// announces 256 or more and requests the short-form maximum.
  public static func getResponse(announcedCount: UInt8) -> Self {
    let expected =
      announcedCount == 0
      ? Iso7816Values.expectedLengthMaximumEncoding
      : announcedCount
    return Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insGetResponse,
        0,
        0,
        expected,
      ])
    )
  }

  /// MANAGE SECURITY ENVIRONMENT: SET the Digital Signature Template to
  /// the authentication key and a signing algorithm
  /// (FINEID S1 v4.2 §3.6).
  ///
  /// Wire shape `00 22 41 B6 06 80 01 <algRef> 84 01 01`. Pins the card
  /// to sign with the PIN1-gated auth key under the given algorithm;
  /// PSO:CDS then produces the signature. Not credential-bearing - the
  /// PIN is verified separately.
  public static func selectSigningEnvironment(
    algorithm: SigningAlgorithm
  ) -> Self {
    let crdo: [UInt8] = [
      FineidValues.crdoAlgorithmReferenceTag,
      FineidValues.crdoValueLength,
      algorithm.reference,
      FineidValues.crdoKeyReferenceTag,
      FineidValues.crdoValueLength,
      FineidValues.keyReferenceAuthentication,
    ]
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insManageSecurityEnvironment,
      Iso7816Values.mseSetP1,
      Iso7816Values.mseDigitalSignatureTemplateP2,
      UInt8(crdo.count),
    ]
    bytes.append(contentsOf: crdo)
    return Self(encoded: Data(bytes))
  }

  /// PERFORM SECURITY OPERATION: COMPUTE DIGITAL SIGNATURE over a
  /// host-supplied digest (FINEID S1 v4.2 §3.8).
  ///
  /// Wire shape `00 2A 9E 9A <Lc> <digest> 00`: the card signs the
  /// digest under the environment selected by
  /// `selectSigningEnvironment` and returns the signature. Digests are
  /// short (<= 64 bytes), so the short form always applies. The card may
  /// answer `6Cxx` (wrong Le) for an ECDSA signature; `CardOperations`
  /// re-issues with the exact length.
  public static func computeSignature(overDigest digest: Data) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insPerformSecurityOperation,
      Iso7816Values.psoComputeSignatureP1,
      Iso7816Values.psoComputeSignatureP2,
      UInt8(digest.count),
    ]
    bytes.append(contentsOf: digest)
    bytes.append(Iso7816Values.expectedLengthMaximumEncoding)
    return Self(encoded: Data(bytes))
  }

  /// PSO:CDS re-issued with an exact Le, answering a `6Cxx` correction.
  public static func computeSignature(
    overDigest digest: Data,
    exactLength: ExpectedResponseLength
  ) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insPerformSecurityOperation,
      Iso7816Values.psoComputeSignatureP1,
      Iso7816Values.psoComputeSignatureP2,
      UInt8(digest.count),
    ]
    bytes.append(contentsOf: digest)
    bytes.append(exactLength.encodedByte)
    return Self(encoded: Data(bytes))
  }

  /// PSO:HASH loading a host-computed digest as the external hash for
  /// the next PSO:CDS (FINEID S1 v4.2 §3.7).
  ///
  /// Wire shape `00 2A 90 A0 <Lc> 90 <len> <digest>`. FINEID auth-key
  /// signing (ECDSA, and pre-hashed RSA) loads the digest here and then
  /// produces the signature with an *empty* PSO:CDS; the digest is never
  /// carried inline in PSO:CDS (that shape draws `6985`). Not
  /// credential-bearing - the PIN is verified separately.
  public static func loadExternalHash(_ digest: Data) -> Self {
    var hashObject: [UInt8] = [
      Iso7816Values.psoHashValueTag,
      UInt8(digest.count),
    ]
    hashObject.append(contentsOf: digest)
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insPerformSecurityOperation,
      Iso7816Values.psoHashP1,
      Iso7816Values.psoHashExternalP2,
      UInt8(hashObject.count),
    ]
    bytes.append(contentsOf: hashObject)
    return Self(encoded: Data(bytes))
  }

  /// PSO:CDS with an empty body, signing the hash previously loaded by
  /// `loadExternalHash` (FINEID S1 v4.2 §3.8).
  ///
  /// Wire shape `00 2A 9E 9A 00`: MSE:SET and PSO:HASH have set the
  /// environment and the digest, so the card just returns the signature.
  /// `Le=00` requests the short-form maximum; an ECDSA card answers
  /// `6Cxx` with the exact length and `CardOperations` re-issues.
  public static func computeSignatureOverLoadedHash() -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insPerformSecurityOperation,
        Iso7816Values.psoComputeSignatureP1,
        Iso7816Values.psoComputeSignatureP2,
        Iso7816Values.expectedLengthMaximumEncoding,
      ])
    )
  }

  /// Empty-body PSO:CDS re-issued with an exact Le, answering a `6Cxx`
  /// correction from the loaded-hash signature.
  public static func computeSignatureOverLoadedHash(
    exactLength: ExpectedResponseLength
  ) -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insPerformSecurityOperation,
        Iso7816Values.psoComputeSignatureP1,
        Iso7816Values.psoComputeSignatureP2,
        exactLength.encodedByte,
      ])
    )
  }

  /// The counter-safe PIN-container query (FINEID S1 v4.2 §3.15.2).
  ///
  /// GET DATA `00 CB 00 FF 05 A0 03 83 01 ref 00`: reads the PIN
  /// container's attributes without presenting a credential and without
  /// touching any counter. This is how the PUK retry counter is read -
  /// the PUK has no side-effect-free VERIFY probe.
  public static func readCredentialAttributes(role: CredentialRole) -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insGetData,
        FineidValues.pinContainerP1,
        FineidValues.pinContainerP2,
        FineidValues.pinContainerRequestLength,
        FineidValues.pinContainerTemplateTag,
        FineidValues.pinContainerTemplateLength,
        FineidValues.pinReferenceTag,
        FineidValues.pinReferenceLength,
        FineidValues.reference(for: role),
        0,
      ])
    )
  }
}
