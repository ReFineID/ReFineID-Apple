// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_REMOTE_CARD
  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import Observation
  import RappEngine
  import Security

  /// Fetches the public authentication certificate once and publishes it as a
  /// per-user persistent CryptoTokenKit identity.
  ///
  /// Private-key operations stay delegated to the phone relay. macOS
  /// fetches at launch; iOS publishes the certificate the explicit
  /// remote connect already read, so the holder is asked exactly once.
  @MainActor
  @Observable
  internal final class PersistentTokenRegistry {
    // MARK: Static Properties

    internal static let shared = PersistentTokenRegistry()

    // MARK: Static Computed Properties

    private static var driverConfiguration: TKTokenDriver.Configuration? {
      TKTokenDriver.Configuration.driverConfigurations[
        PersistentTokenIdentity.classID
      ]
    }

    internal static var needsIdentity: Bool {
      guard let driver = driverConfiguration, !driver.tokenConfigurations.isEmpty else {
        return true
      }
      return driver.tokenConfigurations.values.contains { $0.configurationData == nil }
    }

    /// Safari's chooser title, matching the local reader token.
    ///
    /// Both certificates on a card share one subject, so the label is the
    /// only field that names the PIN 1 identity in DVV's wording.
    private static var authenticationLabel: String {
      String(localized: "Basic (PIN 1)")
    }

    // MARK: Properties

    /// Who the borrowed certificate names, for the identity row.
    internal private(set) var holderLine: String?

    /// The certificate last published, so a reader mint can restore it.
    internal private(set) var certificateDER: Data?

    private var isRunning = false

    /// Whether the holder's stream advertisement has been seen this run.
    internal var hasSeenHolderAdvertisement = false

    /// Whether that advertisement is on the network right now.
    ///
    /// Loss after a find is the signal to withdraw the borrowed identity.
    internal var holderIsAdvertising = false

    #if REFINEID_STREAM_TRANSPORT
      internal var presence: StreamRelayPresence?

      /// Withdraws the identity after Bonjour has omitted the holder
      /// for ``advertisementLossHold``.
      internal var advertisementLossTask: Task<Void, Never>?
    #endif

    // MARK: Lifecycle

    private init() {
      // singleton
    }

    // MARK: Static Functions

    /// Publishes an already-fetched certificate as the persistent
    /// identity.
    internal static func publish(certificateDER: Data) {
      Self.publish(certificateDER, cardSerial: nil)
    }

    /// Publishes an already-fetched certificate with its card serial.
    internal static func publish(certificateDER: Data, cardSerial: String?) {
      Self.publish(certificateDER, cardSerial: cardSerial)
    }

    /// Withdraws every identity this driver has published.
    ///
    /// The published certificate is what Safari offers, so an identity the
    /// holder has dropped has to leave the registry too; leaving it there
    /// would keep offering a card this device can no longer reach.
    internal static func withdraw() {
      withdrawPublishedIdentity()
    }

    /// Removes the published identity.
    ///
    /// The pairing is separate: a reader card leaving withdraws the
    /// borrowed certificate and leaves the pair so the next card can
    /// use it.
    internal static func withdrawPublishedIdentity() {
      guard let driver = driverConfiguration else { return }
      for instanceID in driver.tokenConfigurations.keys {
        driver.removeTokenConfiguration(for: instanceID)
      }
      shared.holderLine = nil
      shared.certificateDER = nil
      #if os(macOS)
        LoginIdentityModel.shared.refresh()
      #endif
    }

    /// The certificate this driver is currently offering, if any.
    ///
    /// What has been published outlives the app that published it, so a
    /// screen that only ever learned an identity by fetching one showed
    /// nothing on every launch after the first while the browser was still
    /// being offered the very same certificate.
    internal static func publishedCertificateDER() -> Data? {
      guard let driver = driverConfiguration else { return nil }
      for configuration in driver.tokenConfigurations.values {
        guard
          let item = try? configuration.certificate(
            for: PersistentTokenIdentity.certificateObjectID
          )
        else {
          continue
        }
        return item.data
      }
      return nil
    }

    private static func makeKeychainItems(
      for certificate: SecCertificate,
      profile: CardKeyProfile
    ) -> (TKTokenKeychainCertificate, TKTokenKeychainKey)? {
      guard
        let certificateItem = TKTokenKeychainCertificate(
          certificate: certificate,
          objectID: PersistentTokenIdentity.certificateObjectID
        ),
        let keyItem = TKTokenKeychainKey(
          certificate: certificate,
          objectID: PersistentTokenIdentity.keyObjectID
        )
      else {
        return nil
      }
      certificateItem.label = authenticationLabel
      keyItem.label = authenticationLabel
      keyItem.keyType = profile.keyType
      keyItem.keySizeInBits = profile.keySizeInBits
      keyItem.canSign = true
      keyItem.canDecrypt = false
      keyItem.canPerformKeyExchange = false
      keyItem.isSuitableForLogin = true
      return (certificateItem, keyItem)
    }

    private static func publish(_ certificateDER: Data, cardSerial: String? = nil) {
      guard
        let driver = driverConfiguration,
        let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: certificate),
        let (certificateItem, keyItem) = makeKeychainItems(
          for: certificate,
          profile: profile
        )
      else {
        return
      }

      let serialPart: String
      if let cardSerial, !cardSerial.isEmpty {
        serialPart = cardSerial.lowercased()
      } else {
        serialPart =
          SHA256.hash(data: certificateDER)
          .map { String(format: "%02x", $0) }
          .joined()
      }

      let instanceID = PersistentTokenIdentity.instancePrefix + serialPart
      // One borrowed identity. addTokenConfiguration appends; leftover
      // instance names from earlier publishes stay in Safari's picker.
      for existingID in driver.tokenConfigurations.keys {
        driver.removeTokenConfiguration(for: existingID)
      }
      let configuration = driver.addTokenConfiguration(for: instanceID)
      let vault = RappDeviceVault()
      let pairID = (try? vault.selectedPairID()) ?? (try? vault.activePairIDs().first)
      if let pairID,
        let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault),
        let pairBytes = try? pair.encodedBytes()
      {
        configuration.configurationData = pairBytes
      }
      // The leaf and its key, and nothing else. Publishing the issuer
      // beside them stopped the browser forming an identity at all:
      // measured on the requester, a configuration of three items was
      // never offered, and the same two were offered at once.
      configuration.keychainItems = [certificateItem, keyItem]
      shared.certificateDER = certificateDER
      shared.holderLine = DistinguishedName.holderLine(fromCertificate: certificateDER)
      #if os(macOS)
        LoginIdentityModel.shared.refresh()
      #endif
      #if DEBUG
        print("[persistent-token] published \(instanceID)")
        fflush(stdout)
      #endif
    }

    // MARK: Functions

    /// Fetches and publishes once at launch on the requesting device when
    /// an identity is needed.
    internal func start() {
      #if REFINEID_STREAM_TRANSPORT
        startWatchingPresence()
        // A leftover identity from an earlier run is not a live card.
        // The pairing stays; publication resumes when the holder is seen.
        if !holderIsAdvertising {
          Self.withdrawPublishedIdentity()
        }
      #else
        seedHolderLine()
      #endif
      startFetch(replacing: false)
    }

    /// Fetches the borrowed certificate after a pairing, replacing any
    /// identity a previous pair left behind.
    internal func startAfterPairing() {
      #if REFINEID_STREAM_TRANSPORT
        startWatchingPresence()
      #endif
      startFetch(replacing: true)
    }

    /// Writes the borrowed certificate again if this process still holds it.
    ///
    /// A live reader token does not own the remote-card driver; restoring
    /// here keeps the wireless identity listed beside a plugged-in card.
    /// A leftover identity is not restored while the holder is absent.
    internal func ensurePublished() {
      #if REFINEID_STREAM_TRANSPORT
        guard holderIsAdvertising else { return }
      #endif
      if !Self.needsIdentity {
        seedHolderLine()
        return
      }
      guard let der = certificateDER ?? Self.publishedCertificateDER() else { return }
      Self.publish(der)
    }

    /// Fills the person line from a certificate this process already holds.
    internal func seedHolderLine() {
      guard let der = certificateDER ?? Self.publishedCertificateDER() else { return }
      certificateDER = der
      if holderLine == nil {
        holderLine = DistinguishedName.holderLine(fromCertificate: der)
      }
    }

    internal func startFetch(replacing: Bool) {
      guard !isRunning else { return }
      guard replacing || Self.needsIdentity || certificateDER == nil else { return }
      isRunning = true
      Task.detached(priority: .userInitiated) {
        let fetched: Data?
        let fetchedSerial: String?
        #if os(macOS)
          let displayName = String(localized: "RefineID Mac")
        #else
          let displayName = String(localized: "RefineID iPad")
        #endif
        do {
          let response = try RappPersistentRequesterClient(
            displayName: displayName
          ).perform(.readAuthenticationCertificate)
          guard case .authenticationCertificate(let certificate, let cardSerial) = response else {
            await Self.shared.finish(nil, cardSerial: nil)
            return
          }
          fetched = certificate
          fetchedSerial = cardSerial
        } catch {
          fetched = nil
          fetchedSerial = nil
        }
        await Self.shared.finish(fetched, cardSerial: fetchedSerial)
      }
    }

    fileprivate func finish(_ certificateDER: Data?, cardSerial: String? = nil) {
      defer { isRunning = false }
      guard let certificateDER else {
        #if REFINEID_STREAM_TRANSPORT
          let retryDelayNs: UInt64 = 2_000_000_000
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: retryDelayNs)
            guard self.holderIsAdvertising,
              Self.needsIdentity || self.certificateDER == nil
            else { return }
            self.startFetch(replacing: true)
          }
        #endif
        return
      }
      holderIsAdvertising = true
      hasSeenHolderAdvertisement = true
      Self.publish(certificateDER, cardSerial: cardSerial)
    }
  }
#endif
