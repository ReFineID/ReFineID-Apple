// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  internal enum CardReaderPinStore {
    /// Verifies PIN 1 with the card in the reader and saves to keychain on success.
    @MainActor
    internal static func verifyAndSave(
      _ pin1: String,
      model: CardCredentialsModel
    ) async -> String? {
      let outcome = await CardMaintenance.onReaderCard(
        cardAccessNumber: nil
      ) { (operations: CardOperations) -> String? in
        do {
          guard let pin1Input = Pin1(digits: pin1) else {
            return String(localized: "Invalid PIN 1 format.")
          }
          try operations.verifyPin1(pin1Input.consumeForSingleTransmission())
          return nil
        } catch CardOperationError.pinRejected(let remaining) {
          let count = remaining.attemptsRemaining
          return String(localized: "Wrong PIN 1. \(count) attempts remaining.")
        } catch CardOperationError.pinBlocked {
          return String(localized: "PIN 1 is blocked.")
        } catch {
          return String(localized: "Could not verify PIN 1 with the card.")
        }
      }
      switch outcome {
      case .connected(let failure):
        if let failure {
          return failure
        }
        _ = model.savePin1(pin1)
        model.refresh()
        return nil
      default:
        return String(localized: "Could not connect to the card in the reader.")
      }
    }
  }
#endif
