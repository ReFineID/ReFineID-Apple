// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_REMOTE_CARD
  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import Observation
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

    private static var needsIdentity: Bool {
      driverConfiguration?.tokenConfigurations.isEmpty ?? true
    }

    // MARK: Properties

    /// Who the borrowed certificate names, for the identity row.
    internal private(set) var holderLine: String?

    /// The certificate last published, so a reader mint can restore it.
    private var certificateDER: Data?

    private var isRunning = false

    // MARK: Lifecycle

    private init() {
      // singleton
    }

    // MARK: Static Functions

    /// Publishes an already-fetched certificate as the persistent
    /// identity.
    internal static func publish(certificateDER: Data) {
      Self.publish(certificateDER)
    }

    /// Withdraws every identity this driver has published.
    ///
    /// The published certificate is what Safari offers, so an identity the
    /// holder has dropped has to leave the registry too; leaving it there
    /// would keep offering a card this device can no longer reach.
    internal static func withdraw() {
      guard let driver = driverConfiguration else { return }
      for instanceID in driver.tokenConfigurations.keys {
        driver.removeTokenConfiguration(for: instanceID)
      }
      shared.holderLine = nil
      shared.certificateDER = nil
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
      for certificate: SecCertificate
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
      certificateItem.label = "ReFineID authentication certificate"
      keyItem.label = "ReFineID authentication key"
      keyItem.canSign = true
      // swiftlint:disable:next legacy_objc_type
      let signOperationKey = NSNumber(value: TKTokenOperation.signData.rawValue)
      keyItem.constraints = [
        signOperationKey: true
      ]
      return (certificateItem, keyItem)
    }

    private static func publish(_ certificateDER: Data) {
      guard
        let driver = driverConfiguration,
        let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
        CardKeyProfile.resolve(fromCertificate: certificate) != nil,
        let (certificateItem, keyItem) = makeKeychainItems(for: certificate)
      else {
        return
      }

      let serialPart: String
      if let facts = CertificateFacts(der: certificateDER),
        let identifier = DistinguishedName.identifier(inName: facts.subjectName)?.lowercased(),
        !identifier.isEmpty
      {
        serialPart = identifier
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
      // The leaf and its key, and nothing else. Publishing the issuer
      // beside them stopped the browser forming an identity at all:
      // measured on the requester, a configuration of three items was
      // never offered, and the same two were offered at once.
      configuration.keychainItems = [certificateItem, keyItem]
      shared.certificateDER = certificateDER
      shared.holderLine = DistinguishedName.holderLine(fromCertificate: certificateDER)
      #if DEBUG
        print("[persistent-token] published \(instanceID)")
        fflush(stdout)
      #endif
    }

    // MARK: Functions

    /// Fetches and publishes once at launch on the requesting device when
    /// an identity is needed.
    internal func start() {
      seedHolderLine()
      startFetch(replacing: false)
    }

    /// Fetches the borrowed certificate after a pairing, replacing any
    /// identity a previous pair left behind.
    internal func startAfterPairing() {
      startFetch(replacing: true)
    }

    /// Writes the borrowed certificate again if this process still holds it.
    ///
    /// A live reader token does not own the remote-card driver; restoring
    /// here keeps the wireless identity listed beside a plugged-in card.
    internal func ensurePublished() {
      if !Self.needsIdentity {
        seedHolderLine()
        return
      }
      guard let der = certificateDER ?? Self.publishedCertificateDER() else { return }
      Self.publish(der)
    }

    private func seedHolderLine() {
      guard let der = certificateDER ?? Self.publishedCertificateDER() else { return }
      certificateDER = der
      if holderLine == nil {
        holderLine = DistinguishedName.holderLine(fromCertificate: der)
      }
    }

    private func startFetch(replacing: Bool) {
      guard !isRunning else { return }
      guard replacing || Self.needsIdentity else { return }
      isRunning = true
      Task.detached(priority: .userInitiated) {
        let fetched: Data?
        #if os(macOS)
          let displayName = String(localized: "ReFineID Mac")
        #else
          let displayName = String(localized: "ReFineID iPad")
        #endif
        do {
          let response = try RappPersistentRequesterClient(
            displayName: displayName
          ).perform(.readAuthenticationCertificate)
          guard case .authenticationCertificate(let certificate) = response else {
            await Self.shared.finish(nil)
            return
          }
          fetched = certificate
        } catch {
          fetched = nil
        }
        await Self.shared.finish(fetched)
      }
    }

    private func finish(_ certificateDER: Data?) {
      defer { isRunning = false }
      guard let certificateDER else { return }
      Self.publish(certificateDER)
    }
  }
#endif
