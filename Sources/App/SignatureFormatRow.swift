//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
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
