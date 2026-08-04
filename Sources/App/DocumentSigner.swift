#if os(macOS)

  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Dispatch
  import Foundation
  import Security

  /// Signs one PDF at the archival level (PAdES-B-LTA).
  ///
  /// The order is forced by what each step attests. The signature is
  /// prepared and taken first; its timestamp proves the signature
  /// existed; the validation material proves the chain was good; and
  /// the archive timestamp, taken last over everything, proves all of
  /// it existed before the algorithms or certificates age. Nothing
  /// below that level is offered: a signature that cannot outlive its
  /// certificates is not what this is for.
  internal enum DocumentSigner {
    /// Why a document could not be signed.
    internal enum Failure: Error {
      /// The card refused, or its qualified slot is unusable.
      case card(CardMaintenance.Outcome)

      /// The document could not be prepared.
      case document(PdfSigningError)

      /// A network step an archival signature cannot omit failed.
      case network(Error)

      /// Complete, authenticated LT evidence could not be collected.
      case validation(Error)
    }

    /// What one card session produced.
    private struct CardMaterial {
      /// The prepared document and its reserved hole.
      let placeholder: PdfSignaturePlaceholder

      /// The exact attribute bytes the card signed.
      let signedAttributes: Data

      /// The card's raw signature over them.
      let signature: Data

      /// The qualified certificate, for the CMS and the chain walk.
      let certificate: Data
    }

    /// Signs `document`, answering the finished bytes.
    internal static func sign(
      _ document: Data,
      pin2: String,
      reason: String?,
      location: String?
    ) async throws -> Data {
      let claim = PdfIncrementalSigner.SignatureClaim(
        signedAt: Date(), reason: reason, location: location
      )
      let material = try await Self.cardMaterial(
        pin2: pin2, document: document, claim: claim
      )
      let verifiedTokens = try await Self.timestamped(material.signature)
      let tokens = verifiedTokens.map(\.token)
      let cms = try QualifiedDocumentCms.assemble(
        signedAttributesSet: material.signedAttributes,
        rawSignature: material.signature,
        signerCertificate: material.certificate,
        timestampTokens: tokens
      )
      let signed = try material.placeholder.filled(with: cms)
      let evidence: PdfValidationStore.Material
      do {
        evidence = try await ValidationMaterialCollector.collect(
          signerCertificate: material.certificate,
          timestampTokens: verifiedTokens
        )
      } catch {
        throw Failure.validation(error)
      }
      let withEvidence = try PdfValidationStore.appended(
        to: signed, material: evidence
      )
      return try await Self.archiveTimestamped(withEvidence)
    }

    /// Reads the qualified certificate, verifies PIN2 and signs, in
    /// one exclusive card session.
    private static func cardMaterial(
      pin2: String,
      document: Data,
      claim: PdfIncrementalSigner.SignatureClaim
    ) async throws -> CardMaterial {
      let prepared: PdfSignaturePlaceholder
      do {
        prepared = try PdfIncrementalSigner.prepare(
          document, revision: .signature(claim)
        )
      } catch let error as PdfSigningError {
        throw Failure.document(error)
      }
      let digest = prepared.digest
      let answer = await CardMaintenance.qualifiedSignature(pin2: pin2) {
        certificate in
        QualifiedDocumentCms.signedAttributes(
          byteRangeDigest: digest, signerCertificate: certificate
        )
      }
      switch answer {
      case .signed(let product):
        return CardMaterial(
          placeholder: prepared,
          signedAttributes: product.attributes,
          signature: product.signature,
          certificate: product.certificate
        )
      case .refused(let outcome):
        throw Failure.card(outcome)
      }
    }

    /// One signature timestamp; an archival signature cannot skip it.
    private static func timestamped(
      _ signature: Data
    ) async throws -> [TimestampTokenVerifier.VerifiedToken] {
      let der = try QualifiedDocumentCms.derSignature(signature)
      do {
        return [try await TimestampClient.token(over: Data(SHA384.hash(data: der)))]
      } catch {
        throw Failure.network(error)
      }
    }

    /// The archive timestamp over the finished file.
    private static func archiveTimestamped(_ document: Data) async throws -> Data {
      let prepared: PdfSignaturePlaceholder
      do {
        prepared = try PdfIncrementalSigner.prepare(
          document, revision: .documentTimestamp
        )
      } catch let error as PdfSigningError {
        throw Failure.document(error)
      }
      do {
        let token = try await TimestampClient.token(over: prepared.digest)
        return try prepared.filled(with: token.token)
      } catch let error as PdfSigningError {
        throw Failure.document(error)
      } catch {
        throw Failure.network(error)
      }
    }
  }

#endif
