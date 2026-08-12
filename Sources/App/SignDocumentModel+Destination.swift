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

    /// The name a container covering several documents is offered
    /// under: the instant it was signed, and nothing else.
    ///
    /// No document in a set is the set. Naming the container after one
    /// of them - whichever happened to be chosen first or last - is a
    /// guess, and a guess that looks like a fact is worse than a blank
    /// a holder fills in. The signing instant is kept because it is
    /// the one part that is not a guess, and because it is what stops
    /// a second signature from overwriting the first.
    nonisolated internal static func suggestedContainerName(
      at instant: Date
    ) -> String {
      let stamped = Self.destination(
        for: URL(fileURLWithPath: "x"), at: instant, format: .asice
      ).lastPathComponent
      return String(stamped.dropFirst("x".count))
    }
  }

#endif
