// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

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

    /// The name the holder wrote for a container, stamped with the
    /// signing instant.
    ///
    /// No document in a set is the set, so a container's name is not
    /// suggested at all: the save panel's field is left empty and the
    /// holder writes one. The instant is appended here, after the
    /// panel - a stamp placed in the field would be wiped by the
    /// first keystroke, since the panel selects everything in it.
    /// Appended, it survives without having to be defended, and it is
    /// what stops a second signature from overwriting the first.
    nonisolated internal static func stampedContainer(
      from chosen: URL,
      at instant: Date
    ) -> URL {
      Self.destination(for: chosen, at: instant, format: .asice)
    }
  }

#endif
