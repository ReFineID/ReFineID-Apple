import Foundation

/// The signing operations: the MSE / PSO:HASH / PSO:CDS chain for both
/// card keys.
///
/// One shared core drives the chain; the public entry points differ
/// only in the key they name and the PIN their contracts demand.
extension CardOperations {
  /// Computes an authentication signature over `digest` with the
  /// PIN1-gated key.
  ///
  /// PIN1 must already be verified in this session.
  public func computeAuthenticationSignature(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> Data {
    try computeSignature(
      overDigest: digest,
      algorithm: algorithm,
      key: .authentication,
      expectedSignatureLength: expectedSignatureLength
    )
  }

  /// Computes a qualified signature over `digest` with the PIN2-gated
  /// key.
  ///
  /// PIN2 must have been verified in this session, immediately before
  /// this call - it is never cached, so one verification serves one
  /// signature.
  public func computeQualifiedSignature(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> Data {
    try computeSignature(
      overDigest: digest,
      algorithm: algorithm,
      key: .qualifiedSignature,
      expectedSignatureLength: expectedSignatureLength
    )
  }

  /// Drives the FINEID sign chain (S1 v4.2 §3.6-3.8).
  ///
  /// MSE:SET DST pins the key and algorithm; PSO:HASH loads the host
  /// digest as the external hash; an empty PSO:CDS then returns the
  /// signature. The digest is loaded via PSO:HASH, never carried inline
  /// in PSO:CDS - the card rejects the inline shape.
  ///
  /// P-384 carries its exact 96-byte signature length as `Le` up front.
  /// The G4E card is T=0-only and a `6Cxx` between PSO:HASH and a re-issued
  /// PSO:CDS can drop the loaded hash, making the card sign
  /// silently-meaningless bytes (S1 v4.2 §3.8.1.1), so this path never
  /// retries that operation. RSA-3072 cannot fit an exact short `Le`; it
  /// uses `00` and the transport keeps its continuation within the
  /// operation. The key's gating PIN must already be verified in this
  /// session. Returns the raw card signature: `r || s` for ECDSA, or one
  /// modulus-wide block for RSA.
  private func computeSignature(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    key: CardSigningKey,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> Data {
    let selected = try transmit(
      .selectSigningEnvironment(algorithm: algorithm, key: key)
    )
    guard selected.statusWord == .success else {
      throw CardOperationError.signRejected(selected.statusWord)
    }
    let hashed = try transmit(.loadExternalHash(digest))
    guard hashed.statusWord == .success else {
      throw CardOperationError.signRejected(hashed.statusWord)
    }
    let signatureCommand =
      expectedSignatureLength.map(CommandApdu.computeSignatureOverLoadedHash(exactLength:))
      ?? .computeSignatureOverLoadedHash()
    let signed = try transmitSignature(signatureCommand)
    guard signed.statusWord == .success else {
      throw CardOperationError.signRejected(signed.statusWord)
    }
    return signed.payload
  }

  /// Diagnostic sibling of `computeAuthenticationSignature` that records
  /// each command's status word instead of throwing at the first
  /// non-`9000`, so a probe can isolate which step a card rejects.
  ///
  /// Returns the raw signature when the chain completes, plus the
  /// `(command, statusWord)` of every command sent. Not on the shipping
  /// token path - that uses the throwing variant above.
  public func computeAuthenticationSignatureTraced(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> (raw: Data?, steps: [(command: String, statusWord: UInt16)]) {
    var steps: [(command: String, statusWord: UInt16)] = []
    let selected = try transmit(
      .selectSigningEnvironment(algorithm: algorithm, key: .authentication)
    )
    steps.append((command: "MSE:SET", statusWord: selected.statusWord.encoded))
    guard selected.statusWord == .success else { return (nil, steps) }
    let hashed = try transmit(.loadExternalHash(digest))
    steps.append((command: "PSO:HASH", statusWord: hashed.statusWord.encoded))
    guard hashed.statusWord == .success else { return (nil, steps) }
    let signatureCommand =
      expectedSignatureLength.map(CommandApdu.computeSignatureOverLoadedHash(exactLength:))
      ?? .computeSignatureOverLoadedHash()
    let signed = try transmitSignature(signatureCommand)
    steps.append((command: "PSO:CDS", statusWord: signed.statusWord.encoded))
    guard signed.statusWord == .success else { return (nil, steps) }
    return (signed.payload, steps)
  }

  /// Transmits PSO:CDS without applying the short-response parser cap.
  ///
  /// RSA-3072 returns 384 bytes. A structured CTK send may deliver the
  /// whole continued result in one callback, while a raw reader path may
  /// still expose `61xx`; ``ContinuedResponse`` handles both forms.
  private func transmitSignature(_ command: CommandApdu) throws -> ResponseApdu {
    let response = try ContinuedResponse.transmitting(command.encoded, over: channel)
    return ResponseApdu(payload: response.payload, statusWord: response.statusWord)
  }
}
