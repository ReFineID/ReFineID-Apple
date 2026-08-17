// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import Foundation
  import Observation

  /// The requester's view of the selected remote card.
  ///
  /// Connecting asks the paired card holder for the authentication
  /// certificate; the holder approves the request and presents the card.
  /// The certificate's subject then names the person on this screen.
  @MainActor
  @Observable
  internal final class RemoteCardModel {
    internal enum Phase: Equatable {
      case idle
      case connecting
      case identity(String)
      case failed
    }

    internal private(set) var phase = Phase.idle

    /// Whether a requester pairing exists to connect through.
    internal private(set) var hasPair = false

    /// The person shown once the remote card has answered.
    internal var holder: String? {
      if case .identity(let holder) = phase { return holder }
      return nil
    }

    /// A pairing lives only inside its connection, and no requester-side
    /// holder keeps one for this screen yet, so no remote card is
    /// available to connect through.
    internal func refresh() {
      hasPair = false
      phase = .idle
    }

    /// Reads the holder from the remote card's authentication
    /// certificate.
    internal func connect() {
      guard phase != .connecting else { return }
      phase = .connecting
      Task.detached(priority: .userInitiated) { [weak self] in
        let response = try? RappPersistentRequesterClient(
          displayName: String(localized: "ReFineID iPad")
        ).perform(.readAuthenticationCertificate)
        let holder: String?
        if case .authenticationCertificate(let der) = response,
          let facts = CertificateFacts(der: der),
          let name = DistinguishedName.personalName(inName: facts.subjectName)
            ?? DistinguishedName.commonName(inName: facts.subjectName)
        {
          let identifier = DistinguishedName.identifier(
            inName: facts.subjectName)
          holder = identifier.map { "\(name) \($0)" } ?? name
          // The same answered certificate becomes the Safari identity;
          // the holder is asked exactly once for both.
          await PersistentTokenRegistry.publish(certificateDER: der)
        } else {
          holder = nil
        }
        await self?.finishConnect(holder: holder)
      }
    }

    private func finishConnect(holder: String?) {
      phase = holder.map(Phase.identity) ?? .failed
    }
  }

#endif
