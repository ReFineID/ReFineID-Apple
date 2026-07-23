import Foundation

/// The read-only card operations of the minimal driver, written against
/// `CardChannel` so every flow is testable without hardware.
///
/// One value serves one exclusive card session. Every operation here is
/// idempotent and credential-free; PIN-bearing flows are a separate,
/// noncopyable path.
public struct CardOperations {
  /// Upper bound on GET RESPONSE continuations for one command; a card
  /// announcing more is misbehaving.
  private static let maximumContinuations = 128

  private let channel: any CardChannel

  /// Wraps one exclusive session's transport.
  public init(channel: any CardChannel) {
    self.channel = channel
  }

  private static func classify(_ statusWord: StatusWord) -> RetryProbeOutcome {
    switch statusWord {
    case .success:
      .verified
    case .pinIncorrect(let remaining):
      .remaining(remaining)
    case .authenticationFailed:
      .noInformation
    case .authenticationBlocked:
      .locked
    case .referenceDataInvalidated:
      .invalidated
    default:
      .other(statusWord.encoded)
    }
  }

  /// Selects the FINEID eID application; the card's DF becomes current.
  ///
  /// Success is also the "supported card" signal: an absent application
  /// answers `fileNotFound`.
  public func selectFineidApplication() throws {
    let response = try transmit(
      .selectApplication(.fineidApplication)
    )
    guard response.statusWord == .success else {
      throw CardOperationError.selectRejected(response.statusWord)
    }
  }

  /// Selects and reads one EF under the current DF to its end.
  public func readElementaryFile(
    _ file: FileIdentifier,
    expectedLength: Int?
  ) throws -> Data {
    let selected = try transmit(.selectElementaryFile(file))
    guard selected.statusWord == .success else {
      throw CardOperationError.selectRejected(selected.statusWord)
    }
    var assembler = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: expectedLength
    )
    return try drive(&assembler)
  }

  /// Reads one certificate's DER bytes from its slot.
  ///
  /// Navigates to the slot's directory, selects the certificate EF, and
  /// reads it to the end. Returns the raw DER: CardCore never parses
  /// X.509 - the platform does (`SecCertificateCreateWithData`). An
  /// absent slot answers `fileNotFound` at selection, surfaced as
  /// `selectRejected` so callers can treat it as "not provisioned".
  public func readCertificate(_ slot: CertificateSlot) throws -> Data {
    switch slot.directory {
    case .pkcs15Application:
      try selectFineidApplication()
    case .masterFile:
      try selectMasterFile()
    }
    return try readSelectedFile(slot.file)
  }

  /// Selects the master file, trying the proven wire variants in order
  /// (select-by-file-id, then select-by-name) since card generations
  /// differ.
  private func selectMasterFile() throws {
    try selectFirstThatSucceeds([
      .selectFile(.masterFile, selectionP1: Iso7816Values.selectByFileIdP1),
      .selectFile(.masterFile, selectionP1: Iso7816Values.selectByAidP1),
    ])
  }

  /// Selects the EF then reads exactly its single DER object.
  ///
  /// The certificate slots hold one DER object. Reading to the
  /// DER-declared length (not the padded file end) is required: the
  /// card refuses a READ BINARY that overruns the file, so a whole-file
  /// read truncates the certificate.
  private func readSelectedFile(_ file: FileIdentifier) throws -> Data {
    try selectFirstThatSucceeds([
      .selectElementaryFile(file),
      .selectFile(file, selectionP1: Iso7816Values.selectByFileIdP1),
    ])
    var assembler = BinaryReadAssembler(mode: .singleDerObject)
    return try drive(&assembler)
  }

  /// Drives an assembler to completion over the transport.
  private func drive(_ assembler: inout BinaryReadAssembler) throws -> Data {
    while case .transmit(let command) = assembler.nextStep {
      assembler.accept(try transmit(command))
    }
    switch assembler.nextStep {
    case .complete(let content):
      return content
    case .failed(let failure):
      throw CardOperationError.readFailed(failure)
    case .transmit:
      throw CardOperationError.malformedResponse
    }
  }

  /// Transmits each command until one answers success; throws
  /// `selectRejected` with the last status if none do.
  private func selectFirstThatSucceeds(_ commands: [CommandApdu]) throws {
    var lastStatus = StatusWord.other(0)
    for command in commands {
      let response = try transmit(command)
      if response.statusWord == .success {
        return
      }
      lastStatus = response.statusWord
    }
    throw CardOperationError.selectRejected(lastStatus)
  }

  /// Probes one credential's retry counter without side effects: the
  /// VERIFY probe form for PIN1/PIN2, the GET DATA PIN-container form
  /// for the PUK (which has no VERIFY probe).
  public func probeRetryCounter(role: CredentialRole) throws -> RetryProbeOutcome {
    switch role {
    case .pin1, .pin2:
      let response = try transmit(.readRetryCounter(role: role))
      return Self.classify(response.statusWord)
    case .puk:
      let response = try transmit(
        .readCredentialAttributes(role: .puk)
      )
      guard response.statusWord == .success else {
        return Self.classify(response.statusWord)
      }
      guard
        let counter = CredentialAttributes.retryCounter(
          fromResponseBody: response.payload
        )
      else {
        return .noInformation
      }
      return .remaining(counter)
    }
  }

  /// Probes all three credentials for the status display and the
  /// cache-admission reading.
  public func probeCredentials() throws -> CredentialProbeReport {
    CredentialProbeReport(
      pin1: try probeRetryCounter(role: .pin1),
      pin2: try probeRetryCounter(role: .pin2),
      puk: try probeRetryCounter(role: .puk)
    )
  }

  /// Verifies PIN1, consuming the one-shot credential.
  ///
  /// Sends VERIFY with the padded PIN block (the noncopyable transport
  /// value guarantees at most one card command). Returns normally only
  /// on `9000`; a wrong PIN throws `pinRejected` carrying the remaining
  /// attempts, and any other answer throws `pinVerifyFailed`. The caller
  /// must already have cleared the retry floor.
  public func verifyPin1(_ transmission: consuming Pin1Transmission) throws {
    let command = CredentialBearingCommand.verifyPin1(transmission)
    let raw = try channel.transmit(command.intoTransportPayload())
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    switch response.statusWord {
    case .success:
      return
    case .pinIncorrect(let remaining):
      throw CardOperationError.pinRejected(remaining: remaining)
    case .authenticationBlocked:
      throw CardOperationError.pinBlocked
    default:
      throw CardOperationError.pinVerifyFailed(response.statusWord)
    }
  }

  /// Computes an authentication signature over `digest`.
  ///
  /// Drives the FINEID auth-key sign chain (S1 v4.2 §3.6-3.8): MSE:SET
  /// DST pins the auth key and algorithm; PSO:HASH loads the host digest
  /// as the external hash; an empty PSO:CDS then returns the signature.
  /// The digest is loaded via PSO:HASH, never carried inline in PSO:CDS -
  /// the card rejects the inline shape with `6985`.
  ///
  /// PSO:CDS carries the exact signature length as `Le` up front, never
  /// `00` (256). The G4E card is T=0-only and answers an over-long `Le`
  /// with `6Cxx`; the ISO 7816-4 re-issue is not reliably reachable in
  /// every transport, and - worse - a `6Cxx` between PSO:HASH and a
  /// re-issued PSO:CDS can drop the loaded hash, making the card sign
  /// silently-meaningless bytes with no error SW (S1 v4.2 §3.8.1.1). The
  /// ECDSA signature length is fixed by the curve, so it is known up
  /// front; anything other than `9000` here fails closed rather than
  /// re-issuing over a possibly-lost hash. PIN1 must already be verified
  /// in this session. Returns the raw card signature: `r || s` for ECDSA
  /// (convert with `EcdsaSignature`).
  public func computeAuthenticationSignature(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    expectedSignatureLength: ExpectedResponseLength
  ) throws -> Data {
    let selected = try transmit(.selectSigningEnvironment(algorithm: algorithm))
    guard selected.statusWord == .success else {
      throw CardOperationError.signRejected(selected.statusWord)
    }
    let hashed = try transmit(.loadExternalHash(digest))
    guard hashed.statusWord == .success else {
      throw CardOperationError.signRejected(hashed.statusWord)
    }
    let signed = try transmit(
      .computeSignatureOverLoadedHash(exactLength: expectedSignatureLength)
    )
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
    expectedSignatureLength: ExpectedResponseLength
  ) throws -> (raw: Data?, steps: [(command: String, statusWord: UInt16)]) {
    var steps: [(command: String, statusWord: UInt16)] = []
    let selected = try transmit(.selectSigningEnvironment(algorithm: algorithm))
    steps.append((command: "MSE:SET", statusWord: selected.statusWord.encoded))
    guard selected.statusWord == .success else { return (nil, steps) }
    let hashed = try transmit(.loadExternalHash(digest))
    steps.append((command: "PSO:HASH", statusWord: hashed.statusWord.encoded))
    guard hashed.statusWord == .success else { return (nil, steps) }
    let signed = try transmit(
      .computeSignatureOverLoadedHash(exactLength: expectedSignatureLength)
    )
    steps.append((command: "PSO:CDS", statusWord: signed.statusWord.encoded))
    guard signed.statusWord == .success else { return (nil, steps) }
    return (signed.payload, steps)
  }

  /// Reads the full hardware serial from EF.TokenInfo.
  ///
  /// Reads the single DER object (the PKCS#15 TokenInfo SEQUENCE), not to
  /// the padded file end: a whole-file read pulls trailing padding that
  /// the card either refuses (overrun) or that defeats the DER parse -
  /// exactly the failure the certificate reads already avoid.
  public func readTokenSerial() throws -> TokenSerial {
    let selected = try transmit(.selectElementaryFile(.tokenInfo))
    guard selected.statusWord == .success else {
      throw CardOperationError.selectRejected(selected.statusWord)
    }
    var assembler = BinaryReadAssembler(mode: .singleDerObject)
    let content = try drive(&assembler)
    guard let serial = TokenInfoFile.serial(fromContent: content) else {
      throw CardOperationError.tokenInfoMalformed
    }
    return serial
  }

  /// Sends one idempotent command and runs the T=0 `61xx` GET RESPONSE
  /// continuation to completion, bounded in rounds and total size.
  ///
  /// Automatic continuation is safe here precisely because only the
  /// idempotent command class reaches this path; the credential-bearing
  /// path is a separate type and never continues automatically
  /// (Documentation/release-plan.md section 4.3).
  private func transmit(_ command: CommandApdu) throws -> ResponseApdu {
    var response = try transmitOnce(command.encoded)
    var joined = response.payload
    var rounds = 0
    while case .responseAvailable(let count) = response.statusWord {
      rounds += 1
      guard
        rounds <= Self.maximumContinuations,
        joined.count <= BinaryReadAssembler.maximumTotalLength
      else {
        throw CardOperationError.malformedResponse
      }
      response = try transmitOnce(
        CommandApdu.getResponse(announcedCount: count).encoded
      )
      joined.append(response.payload)
    }
    return ResponseApdu(payload: joined, statusWord: response.statusWord)
  }

  private func transmitOnce(_ payload: Data) throws -> ResponseApdu {
    let raw = try channel.transmit(payload)
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    return response
  }
}
