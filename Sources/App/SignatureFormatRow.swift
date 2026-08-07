#if os(macOS)

  import SwiftUI

  /// The signature-shape row: a choice for a PDF, a statement
  /// otherwise.
  ///
  /// ASiC-E is the container format Estonian DigiDoc and other
  /// European tooling exchanges; a PDF can instead carry the signature
  /// inside itself, which is the default because the output stays an
  /// ordinary PDF.
  internal struct SignatureFormatRow: View {
    /// The file waiting to be signed.
    internal let pending: URL

    /// The chosen shape.
    @Binding internal var format: SignatureFormat

    internal var body: some View {
      if SignatureFormat.isPdf(pending) {
        Picker("Format", selection: $format) {
          Text("In the PDF (PAdES)").tag(SignatureFormat.pades)
          Text("Container (ASiC-E)").tag(SignatureFormat.asice)
        }
        .accessibilityIdentifier("signatureFormat")
      } else {
        LabeledContent("Format") {
          Text("Container (ASiC-E)")
        }
      }
    }
  }

#endif
