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

  /// The signed bytes and the validation level actually completed.
  extension DocumentSigner {
    /// One completed document-signing operation.
    internal struct Product: Sendable {
      /// The finished PDF bytes.
      internal let bytes: Data

      /// The evidence level present in those bytes.
      internal let completion: Completion
    }

    /// What evidence was completed after the card signature.
    internal enum Completion: Equatable, Sendable {
      /// Complete PAdES-B-LTA evidence.
      case archival

      #if DEBUG
        /// Debug-only PAdES-B-T output from an authenticated revoked signer.
        case revokedSignerTest
      #endif
    }
  }

#endif
