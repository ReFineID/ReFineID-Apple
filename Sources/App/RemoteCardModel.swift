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

    /// Why the last attempt failed, in the holder's words.
    internal private(set) var failureText: String?

    /// Whether a requester pairing exists to connect through.
    internal private(set) var hasPair = false

    /// The person shown once the remote card has answered.
    internal var holder: String? {
      if case .identity(let holder) = phase { return holder }
      return nil
    }

    /// Re-reads the selected pairing and drops state without one.
    internal func refresh() {
      Task {
        let catalog = RappPairCatalog(vault: RappDeviceVault())
        let selected = try? await catalog.selectedPair()
        hasPair = selected?.role == .requester
        if !hasPair {
          phase = .idle
        }
      }
    }

    /// Reads the holder from the remote card's authentication
    /// certificate.
    internal func connect() {
      guard phase != .connecting else { return }
      phase = .connecting
      Task.detached(priority: .userInitiated) { [weak self] in
        let response: RappRequesterResponse?
        var failure: String?
        do {
          response = try RappPersistentRequesterClient(
            displayName: String(localized: "ReFineID iPad")
          ).perform(.readAuthenticationCertificate)
        } catch let error as RappRequesterClientError {
          response = nil
          failure = remoteFailureText(for: error)
        } catch {
          response = nil
          failure = String(localized: "The remote card could not be read.")
        }
        await self?.setFailureText(failure)
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
      if holder != nil { failureText = nil }
    }

    private func setFailureText(_ text: String?) {
      failureText = text
    }
  }

  /// Names the failure so the holder knows which device to attend to.
  private func remoteFailureText(for error: RappRequesterClientError) -> String {
    switch error {
    case .noActivePair, .noSelectedPair:
      String(localized: "No paired phone. Pair a phone to use its card.")
    case .timedOut:
      String(localized: "The phone did not answer. Open ReFineID on the phone and try again.")
    default:
      String(localized: "The remote card could not be read.")
    }
  }

#endif
