#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Reading the holder's handwritten signature off the card.
  ///
  /// This is the one operation that needs the card access number
  /// rather than a PIN: the signature lives in the travel-document
  /// application, and every file there is sealed until PACE has run.
  /// The number is asked for at the moment it is used and is not
  /// stored - it unlocks reading, so keeping it would be keeping a key
  /// to the holder's own card for no reason.
  ///
  /// Nothing here presents a PIN, so no retry counter is touched, and
  /// a wrong access number costs nothing but a refusal.
  extension CardMaintenance {
    /// Carries the non-Sendable card onto the background queue.
    private final class CarriedCard: @unchecked Sendable {
      let card: TKSmartCard

      init(_ card: TKSmartCard) {
        self.card = card
      }
    }

    /// A signature image and the name that goes with it.
    internal struct Mark: Equatable, Sendable {
      /// The image, as the card stores it.
      internal let bytes: Data

      /// The holder as a person reads it.
      internal let name: String

      /// The identifier the certificate states.
      internal let identifier: String
    }

    /// What reading the signature answered.
    internal enum SignatureOutcome: Equatable {
      /// The card carries no signature image.
      case absent

      /// The image as the card stores it, and the common name its
      /// qualified certificate states.
      case image(Mark)

      /// No card was readable.
      case noCard

      /// The access number was refused, or the secure channel could
      /// not be opened with it.
      case wrongAccessNumber
    }

    /// Reads data group 7 behind a PACE channel opened with `digits`.
    internal static func displayedSignature(
      accessNumber digits: String
    ) async -> SignatureOutcome {
      guard let number = CardAccessNumber(digits: digits) else {
        return .wrongAccessNumber
      }
      let answer = await Self.onTravelDocument(accessNumber: number) {
        operations -> SignatureOutcome in
        guard let image = try? operations.readDisplayedSignature() else {
          return .absent
        }
        // The name is read in the same session, from the certificate
        // that will verify the signature - so what the mark states
        // and what signs the document cannot disagree.
        guard
          let certificate = try? operations.readCertificate(.qualifiedSignature),
          let facts = CertificateFacts(der: certificate),
          let name = DistinguishedName.personalName(inName: facts.subjectName)
            ?? DistinguishedName.commonName(inName: facts.subjectName)
        else {
          return .absent
        }
        return .image(
          Mark(
            bytes: image.bytes,
            name: name,
            identifier: DistinguishedName.identifier(inName: facts.subjectName)
              ?? ""
          )
        )
      }
      return answer ?? .noCard
    }

    /// Opens a session, runs PACE, selects the travel-document
    /// application, and hands the secure-messaged operations to
    /// `work`.
    ///
    /// PACE runs from the master file: an MSE:Set AT from inside an
    /// application context is answered 6985, so the master file is
    /// made current on the plain channel first.
    private static func onTravelDocument<Answer: Sendable>(
      accessNumber: CardAccessNumber,
      _ work: @escaping @Sendable (CardOperations) -> Answer?
    ) async -> Answer? {
      guard let manager = TKSmartCardSlotManager.default,
        let found = await CardSlotSearch.occupied(in: manager),
        let smartCard = found.slot.makeSmartCard()
      else {
        return nil
      }
      let carried = CarriedCard(smartCard)
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? SmartCardChannel(carried.card).withSession {
            channel -> Answer? in
            try? CardOperations(channel: channel).selectMasterFile()
            guard
              let keys = try? PaceEstablishment(channel: channel).establish(
                with: accessNumber
              )
            else {
              return nil
            }
            let operations = CardOperations(
              channel: SecureMessagingChannel(
                wrapping: channel, sessionKeys: keys
              )
            )
            guard
              (try? operations.selectTravelDocumentApplication()) != nil
            else {
              return nil
            }
            return work(operations)
          }
          continuation.resume(returning: answer.flatMap(\.self))
        }
      }
    }
  }

#endif
