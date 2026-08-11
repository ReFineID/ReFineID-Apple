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
  import UniformTypeIdentifiers

  /// The signature shapes one chosen document can be signed into.
  ///
  /// A PDF can carry its own signature (PAdES) or travel inside a
  /// signature container (ASiC-E); any other file type has no inside
  /// to sign, so the container is its only shape.
  internal enum SignatureFormat: Equatable, Sendable {
    /// An ASiC-E container holding the file and an XAdES signature
    /// over it (ETSI EN 319 162-1) - the `.asice`/`.bdoc` format
    /// Estonian DigiDoc and other Baltic tooling exchanges.
    case asice

    /// A PAdES signature embedded in the PDF itself.
    case pades

    /// What the save panel may name the output.
    ///
    /// `.asice` has no type registered on a clean system, so the type
    /// is declared from the extension; falling back to a generic type
    /// keeps the panel usable rather than renaming the output.
    internal var allowedContentTypes: [UTType] {
      switch self {
      case .asice:
        [UTType(filenameExtension: "asice") ?? .data]
      case .pades:
        [.pdf]
      }
    }

    /// The formats offered for `source`, the preferred one first.
    internal static func available(for source: URL) -> [Self] {
      Self.isPdf(source) ? [.pades, .asice] : [.asice]
    }

    /// Whether a file can hold a PAdES signature at all.
    internal static func isPdf(_ source: URL) -> Bool {
      source.pathExtension.lowercased() == "pdf"
    }

    /// The signed output's path extension.
    internal func outputPathExtension(for source: URL) -> String {
      switch self {
      case .asice:
        "asice"
      case .pades:
        source.pathExtension
      }
    }
  }

#endif
