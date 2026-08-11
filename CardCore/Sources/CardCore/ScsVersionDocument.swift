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
import Foundation

/// The `/version` response document (DVV SCS specification v1.3
/// §2.5.2).
///
/// The list-valued fields are comma-separated strings, not JSON
/// arrays - callers split them client-side. The document describes
/// the complete surface this service answers: JSON `/sign` plus the
/// JWT transaction path, data or digest content, and the raw or
/// CMS/PAdES signature forms.
public struct ScsVersionDocument: Codable, Equatable, Sendable {
  /// The document this service publishes.
  public static let current = Self(
    version: ScsValues.version,
    httpMethods: "POST",
    contentTypes: "data,digest",
    signatureTypes: "signature,cms-pades",
    selectorAvailable: true,
    hashAlgorithms: "SHA256,SHA384,SHA512",
    signatureAlgorithms: "RSA,ECDSA",
    applicationOIDs: ""
  )

  /// The protocol version.
  public let version: String

  /// Accepted request methods.
  public let httpMethods: String

  /// Accepted `contentType` values.
  public let contentTypes: String

  /// Accepted `signatureType` values.
  public let signatureTypes: String

  /// Whether the certificate selector is honoured.
  public let selectorAvailable: Bool

  /// Accepted `hashAlgorithm` values.
  public let hashAlgorithms: String

  /// Accepted `signatureAlgorithm` values.
  public let signatureAlgorithms: String

  /// Accepted application object identifiers; none are required.
  public let applicationOIDs: String
}
