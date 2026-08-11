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

  extension SignDocumentModel {
    /// The signed file's place beside the original.
    ///
    /// Stamped with the UTC instant, colons replaced so the name is
    /// safe everywhere. The extension follows the format: the
    /// original's for a PAdES PDF, `.asice` for a container.
    nonisolated internal static func destination(
      for source: URL,
      at instant: Date,
      format: SignatureFormat
    ) -> URL {
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.formatOptions = [.withInternetDateTime]
      let instantText = formatter.string(from: instant)
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "+00-00", with: "Z")
      let name = source.deletingPathExtension().lastPathComponent
      return source.deletingLastPathComponent()
        .appendingPathComponent("\(name) - signed at \(instantText)")
        .appendingPathExtension(format.outputPathExtension(for: source))
    }

    /// The name a signed document should be offered under: the
    /// original's, with the instant it was signed.
    nonisolated internal static func suggestedName(
      for source: URL,
      format: SignatureFormat
    ) -> String {
      Self.destination(for: source, at: Date(), format: format)
        .lastPathComponent
    }
  }

#endif
