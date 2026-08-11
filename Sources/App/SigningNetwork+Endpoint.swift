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

  extension SigningNetwork {
    /// Why the caller is contacting one endpoint.
    ///
    /// Timestamp authorities are configured by the user. Certificate
    /// material addresses are copied from an untrusted certificate and
    /// therefore must resolve only to public addresses.
    internal enum Endpoint: Sendable {
      case authority
      case certificateMaterial
    }

    /// The pure outcome of one redirect-policy decision.
    internal enum RedirectDecision: Equatable {
      case follow
      case refuse
    }
  }

#endif
