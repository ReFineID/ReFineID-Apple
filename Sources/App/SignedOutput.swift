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
    internal static func chooseFile(for source: URL, format: SignatureFormat) -> URL? {
      let panel = NSSavePanel()
      panel.allowedContentTypes = format.allowedContentTypes
      panel.nameFieldStringValue = SignDocumentModel.suggestedName(for: source, format: format)
      panel.directoryURL = source.deletingLastPathComponent()
      panel.message = String(localized: "Where to keep the signed document.")
      panel.prompt = String(localized: "Sign")
      guard panel.runModal() == .OK else { return nil }
      return panel.url
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
