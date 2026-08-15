// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  extension SignDocumentModel {
    /// A signed portrait QR could not be turned into a printable mark.
    internal enum StampPreparationFailure: Error {
      case rendering
    }

    /// One localized failure vocabulary, shared with iOS.
    internal static func message(for error: Error) -> String {
      if error is StampPreparationFailure {
        return String(
          localized: "error.stampRendering",
          defaultValue:
            "The signed portrait QR could not be rendered. Nothing was written.",
          table: "DocumentSigning")
      }
      return DocumentSigningMessage.message(for: error)
    }
  }

#endif
