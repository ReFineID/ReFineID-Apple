#if os(macOS)

  import Foundation

  extension SignDocumentModel {
    /// The signed file's place: beside the original, stamped with the
    /// UTC instant, colons replaced so the name is safe everywhere.
    nonisolated internal static func destination(
      for source: URL,
      at instant: Date
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
        .appendingPathExtension(source.pathExtension)
    }

    /// The name a signed document should be offered under: the
    /// original's, with the instant it was signed.
    nonisolated internal static func suggestedName(for source: URL) -> String {
      Self.destination(for: source, at: Date()).lastPathComponent
    }
  }

#endif
