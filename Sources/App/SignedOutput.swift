// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import Foundation

  /// Where signed documents are written.
  ///
  /// Asked for before the card is touched. The sandbox hands this app
  /// the documents that were dropped and not the folder around them,
  /// so writing beside them has to be granted, and a panel answered
  /// after signing could be cancelled with signatures already spent.
  @MainActor
  internal enum SignedOutput {
    /// Asks for the file one signature is written to.
    ///
    /// A container covering a set is offered no name at all, because
    /// no one document in a set is the set: naming it after whichever
    /// was chosen first would be a guess wearing the look of a fact.
    /// The field is left empty for the holder to write - the panel
    /// will not save on an empty name, so a name is always theirs -
    /// and the signing instant is appended to what they wrote. One
    /// document is offered its own name, which is not a guess.
    internal static func chooseFile(
      for documents: [URL],
      format: SignatureFormat
    ) -> URL? {
      guard let first = documents.first else { return nil }
      let together = documents.count > 1
      let panel = NSSavePanel()
      panel.allowedContentTypes = format.allowedContentTypes
      panel.nameFieldStringValue =
        together ? "" : SignDocumentModel.suggestedName(for: first, format: format)
      panel.directoryURL = first.deletingLastPathComponent()
      panel.message =
        together
        ? String(localized: "Name the container; the signing time is added to the name.")
        : String(localized: "Where to keep the signed document.")
      panel.prompt = String(localized: "Sign")
      guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
      return together ? SignDocumentModel.stampedContainer(from: chosen, at: Date()) : chosen
    }

    /// Asks for the folder a batch is written to, starting beside the
    /// first document.
    internal static func chooseFolder(startingAt origin: URL?) -> URL? {
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.canCreateDirectories = true
      panel.allowsMultipleSelection = false
      panel.directoryURL = origin
      panel.message = String(localized: "Where to keep the signed documents.")
      panel.prompt = String(localized: "Sign")
      guard panel.runModal() == .OK else { return nil }
      return panel.url
    }
  }

#endif
