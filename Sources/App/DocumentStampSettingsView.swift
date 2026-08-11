// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if os(macOS)

  import SwiftUI

  /// Chooses the visible mark placed on signed PDFs.
  internal struct DocumentStampSettingsView: View {
    private static let paneWidth: CGFloat = 520
    private static let paneHeight: CGFloat = 170

    @State private var style = DocumentStampStyle.load()

    internal var body: some View {
      Form {
        Section {
          Picker("Style", selection: $style) {
            Text("Signature, name and SATU")
              .tag(DocumentStampStyle.signatureAndIdentity)
            Text("Portrait QR")
              .tag(DocumentStampStyle.portraitQr)
          }
          .pickerStyle(.radioGroup)
        } header: {
          Text("Visible PDF Stamp")
        } footer: {
          explanation
        }
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.paneWidth, minHeight: Self.paneHeight)
      .onChange(of: style) { _, chosen in
        DocumentStampStyle.save(chosen)
      }
    }

    /// What the selected mark puts on the page.
    @ViewBuilder private var explanation: some View {
      switch style {
      case .signatureAndIdentity:
        Text(
          "The card's handwritten signature appears on a line, with its certificate name and SATU below."
        )
      case .portraitQr:
        Text(
          "The portrait forms a signed QR stamp carrying the document name and signing time."
        )
      }
    }
  }

#endif
