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

  import Foundation

  /// One visible statement and the exact certificate that states it.
  internal struct DocumentStampState {
    internal let statement: StampRenderer.Statement
    internal let signerCertificate: Data
    internal let portrait: Data?

    /// Reuses the exact certificate names captured with the card portrait.
    internal func portraitStatement(
      qrPortrait: QrPortrait.Artwork
    ) -> StampRenderer.Statement {
      StampRenderer.Statement(
        name: statement.name,
        identifier: statement.identifier,
        signature: statement.signature,
        qrPortrait: qrPortrait,
        givenName: statement.givenName,
        surname: statement.surname
      )
    }
  }

#endif
