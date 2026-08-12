// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The signature-shape row: a choice when every document could take
  /// either shape, a statement otherwise.
  ///
  /// ASiC-E is the container format Estonian DigiDoc and other
  /// European tooling exchanges; a PDF can instead carry the signature
  /// inside itself, which is the default because the output stays an
  /// ordinary PDF.
  ///
  /// The choice is offered for the whole pile rather than for the
  /// document whose name shows. One PDF among other file types cannot
  /// make the set signable in place, and offering PAdES there would
  /// take the PIN before the first non-PDF refused it.
  internal struct SignatureFormatRow: View {
    /// Every file waiting to be signed.
    internal let documents: [URL]

    /// The chosen shape.
    @Binding internal var format: SignatureFormat

    /// Whether the signature could go inside each document as it is.
    private var everyOneAPdf: Bool {
      !documents.isEmpty && documents.allSatisfy(SignatureFormat.isPdf)
    }

    internal var body: some View {
      if everyOneAPdf {
        Picker("Format", selection: $format) {
          Text(
            documents.count > 1
              ? "In each PDF (PAdES)" : "In the PDF (PAdES)"
          )
          .tag(SignatureFormat.pades)
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
