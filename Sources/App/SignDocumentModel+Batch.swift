#if os(macOS)

  import Foundation

  /// Signing everything that was dropped, in one pass.
  extension SignDocumentModel {
    /// Signs every queued document into `directory`.
    ///
    /// The folder is granted once, before the card is touched, for the
    /// same reason a single signature asks for its file first: a panel
    /// answered after signing could be cancelled with a signature
    /// already spent.
    ///
    /// One document failing does not stop the rest. Each leaves a
    /// sentence behind, because a batch that reports only that it
    /// finished hides which documents were signed.
    internal func signAll(
      pin2: String,
      accessNumber: String,
      format: SignatureFormat,
      intoDirectory directory: URL
    ) async {
      let instant = Date()
      guard !working else { return }
      let documents = queued
      var outcomes: [String] = []
      for source in documents {
        focus(on: source)
        let destination = directory.appendingPathComponent(
          Self.destination(for: source, at: instant, format: format).lastPathComponent
        )
        await sign(
          pin2: pin2, accessNumber: accessNumber, format: format, to: destination
        )
        if let failure {
          outcomes.append("\(source.lastPathComponent): \(failure)")
        } else {
          outcomes.append(
            String(localized: "\(source.lastPathComponent) signed")
          )
        }
      }
      record(batch: outcomes)
      if let first = documents.first {
        focus(on: first)
      }
    }
  }

#endif
