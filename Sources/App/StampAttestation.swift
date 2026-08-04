#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation

  /// The signed statement the stamp's QR code carries.
  ///
  /// It says four things and nothing else: which file, who signed it,
  /// when a timestamp authority saw that signature, and the signature
  /// itself. It does not attest the paper it is printed on - a QR can
  /// be photocopied onto anything - and the text says so, inside the
  /// bytes that are signed.
  ///
  /// The readable part is the signed part. Any scanner shows the
  /// manifest as text; the detached signature follows it, so what a
  /// bystander reads is exactly what the signature covers.
  ///
  /// Certificates are left out. The holder's own certificate is
  /// larger than everything else here put together, and with it
  /// nothing fits a QR code that survives being folded. A verifier
  /// supplies it: `openssl cms -verify -certfile cert.pem`.
  internal enum StampAttestation {
    /// What the manifest states.
    internal struct Claim {
      /// The document's own name.
      internal let filename: String

      /// The common name the qualified certificate states.
      internal let signer: String
    }

    /// Separates the manifest from the signature that covers it.
    private static let separator = "\n-----BEGIN SIGNATURE-----\n"

    /// The manifest text, which is what gets signed.
    internal static func manifest(_ claim: Claim, at instant: Date) -> Data {
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.formatOptions = [.withInternetDateTime]
      let text = """
        File: \(claim.filename)
        Signer: \(claim.signer)
        Signed: \(formatter.string(from: instant))
        Note: attests the file named above, not the paper it is printed on.
        """
      return Data(text.utf8)
    }

    /// The whole payload: the manifest, then the signature over it.
    internal static func payload(manifest: Data, signature: Data) -> Data {
      manifest + Data(Self.separator.utf8) + signature
    }
  }

#endif
