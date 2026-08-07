#if os(macOS)

  import CardCore
  import Foundation
  import Security
  import UniformTypeIdentifiers

  /// Signs one file into an ASiC-E container at level XAdES-LT.
  ///
  /// The order is forced by what each step attests, exactly as in
  /// `DocumentSigner`: the XAdES `SignedInfo` is prepared and signed
  /// first; its timestamp proves the signature existed; and the
  /// validation material proves the chain was good at that instant.
  /// The container is only assembled once all the evidence is in the
  /// signature document, because a container is one write - there is
  /// no incremental revision to extend later.
  ///
  /// The output is the `.asice` format ETSI EN 319 162-1 defines and
  /// Estonian DigiDoc (BDOC 2.1) exchanges.
  internal enum AsicSigner {
    /// Why a container could not be produced, beyond the shared
    /// card/network/validation failures reported through
    /// `DocumentSigner.Failure`.
    internal enum Failure: Error {
      /// The finished entries could not be described by the container
      /// format's 32-bit fields.
      case container

      /// The card session signed octets that do not match the
      /// signature rebuilt from its certificate.
      case signedOctetsChanged
    }

    /// Fallback media type for a file no type database knows.
    private static let unknownMediaType = "application/octet-stream"

    /// Signs `content` under its file name, answering the container.
    internal static func sign(
      _ content: Data,
      named name: String,
      pin2: String
    ) async throws -> Data {
      let signedAt = Date()
      let object = AsicContainer.DataObject(
        name: name,
        mimeType: Self.mediaType(forFileNamed: name),
        content: content
      )
      let answer = await CardMaintenance.qualifiedSignature(
        pin2: pin2,
        expectedCertificate: nil
      ) { certificate in
        Self.plannedSignedInfo(
          objects: [object], certificate: certificate, signedAt: signedAt
        )
      }
      switch answer {
      case .refused(let outcome):
        throw DocumentSigner.Failure.card(outcome)
      case .signerCertificateMismatch:
        throw DocumentSigner.Failure.stampSignerChanged
      case .signed(let product):
        return try await Self.assembled(
          from: product, object: object, signedAt: signedAt
        )
      }
    }

    /// Timestamps the signature, collects the evidence, and writes the
    /// container.
    private static func assembled(
      from product: CardMaintenance.QualifiedProduct,
      object: AsicContainer.DataObject,
      signedAt: Date
    ) async throws -> Data {
      // The plan is rebuilt from the certificate the card answered
      // with; the card must have signed exactly these octets. A
      // mismatch means the deterministic rebuild does not describe
      // what was signed, and nothing downstream may proceed on it.
      guard
        let plan = XadesSignature.plan(
          objects: [object],
          certificate: product.certificate,
          profile: product.profile,
          signedAt: signedAt
        ),
        product.content == plan.signedInfo,
        let xmlSignature = product.profile.xmlSignature(
          fromWire: product.signature
        )
      else {
        throw Failure.signedOctetsChanged
      }
      let token: TimestampTokenVerifier.VerifiedToken
      do {
        token = try await TimestampClient.token(
          over: XadesSignature.timestampDigest(xmlSignature)
        )
      } catch {
        throw DocumentSigner.Failure.network(error)
      }
      let evidence: PdfValidationStore.Material
      do {
        evidence = try await ValidationMaterialCollector.collect(
          signerCertificate: product.certificate,
          timestampTokens: [token]
        )
      } catch {
        throw DocumentSigner.Failure.validation(error)
      }
      let document = plan.document(
        xmlSignature: xmlSignature,
        timestampTokens: [token.token],
        material: evidence
      )
      guard
        let archive = AsicContainer.container(
          objects: [object], signatureXml: document
        )
      else {
        throw Failure.container
      }
      return archive
    }

    /// The canonical `SignedInfo` octets for the card to sign, built
    /// inside the card session where the certificate first exists.
    ///
    /// Empty on a certificate whose key no profile matches; the
    /// deterministic rebuild in `assembled` then refuses the mismatch
    /// before any output exists.
    private static func plannedSignedInfo(
      objects: [AsicContainer.DataObject],
      certificate: Data,
      signedAt: Date
    ) -> Data {
      guard
        let parsed = SecCertificateCreateWithData(nil, certificate as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: parsed),
        let plan = XadesSignature.plan(
          objects: objects,
          certificate: certificate,
          profile: profile,
          signedAt: signedAt
        )
      else {
        return Data()
      }
      return plan.signedInfo
    }

    /// The media type recorded and signed for a file name.
    internal static func mediaType(forFileNamed name: String) -> String {
      let fileExtension = URL(fileURLWithPath: name).pathExtension
      guard !fileExtension.isEmpty,
        let type = UTType(filenameExtension: fileExtension),
        let mimeType = type.preferredMIMEType
      else {
        return Self.unknownMediaType
      }
      return mimeType
    }
  }

#endif
