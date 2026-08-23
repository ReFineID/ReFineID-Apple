// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_REMOTE_CARD
  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import Security

  /// Fetches the public authentication certificate once and publishes it as a
  /// per-user persistent CryptoTokenKit identity.
  ///
  /// Private-key operations stay delegated to the phone relay. macOS
  /// fetches at launch; iOS publishes the certificate the explicit
  /// remote connect already read, so the holder is asked exactly once.
  @MainActor
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

    private var isRunning = false

    // MARK: Lifecycle

    private init() {}

    // MARK: Static Functions

    /// Publishes an already-fetched certificate as the persistent
    /// identity.
    internal static func publish(certificateDER: Data) {
      #if DEBUG
        print(
          "[PersistentTokenRegistry] publish: certificateDER=\(certificateDER.count)B isRunning=\(shared.isRunning)"
        )
        fflush(stdout)
      #endif
      guard shared.isRunning == false else {
        #if DEBUG
          print("[PersistentTokenRegistry] publish: skipping, isRunning=true")
          fflush(stdout)
        #endif
        return
      }
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

    private static func publish(_ certificateDER: Data) {
      #if DEBUG
        print("[PersistentTokenRegistry] publish: starting")
        fflush(stdout)
      #endif

      guard let driver = driverConfiguration else {
        #if DEBUG
          print("[PersistentTokenRegistry] publish: no driver configuration")
          fflush(stdout)
        #endif
        return
      }

      guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
        #if DEBUG
          print("[PersistentTokenRegistry] publish: failed to create certificate from DER")
          fflush(stdout)
        #endif
        return
      }

      guard let profile = CardKeyProfile.resolve(fromCertificate: certificate) else {
        #if DEBUG
          print("[PersistentTokenRegistry] publish: failed to resolve profile from certificate")
          fflush(stdout)
        #endif
        return
      }

      guard
        let certificateItem = TKTokenKeychainCertificate(
          certificate: certificate,
          objectID: PersistentTokenIdentity.certificateObjectID
        )
      else {
        #if DEBUG
          print("[PersistentTokenRegistry] publish: failed to create certificate item")
          fflush(stdout)
        #endif
        return
      }

      guard
        let keyItem = TKTokenKeychainKey(
          certificate: certificate,
          objectID: PersistentTokenIdentity.keyObjectID
        )
      else {
        #if DEBUG
          print("[PersistentTokenRegistry] publish: failed to create key item")
          fflush(stdout)
        #endif
        return
      }

      #if DEBUG
        print(
          """
          [PersistentTokenRegistry] publish: driver=\(driver), profile=\(profile), \
          certItem=\(certificateItem), keyItem=\(keyItem)
          """
        )
        fflush(stdout)
      #endif

      let instanceID =
        PersistentTokenIdentity.instancePrefix
        + SHA256.hash(data: certificateDER)
        .map { String(format: "%02x", $0) }
        .joined()
      let configuration = driver.addTokenConfiguration(for: instanceID)
      certificateItem.label = "ReFineID authentication certificate"
      keyItem.label = "ReFineID authentication key"
      keyItem.canSign = true
      keyItem.constraints = [
        NSNumber(value: TKTokenOperation.signData.rawValue): true
      ]
      // The leaf and its key, and nothing else. Publishing the issuer
      // beside them stopped the browser forming an identity at all:
      // measured on the requester, a configuration of three items was
      // never offered, and the same two were offered at once.
      configuration.keychainItems = [certificateItem, keyItem]
      #if DEBUG
        print("[persistent-token] published \(instanceID)")
        fflush(stdout)
      #endif
    }

    // MARK: Functions

    /// Fetches and publishes once at launch, on the platform whose
    /// requester runs unattended.
    ///
    /// iOS publishes from the visible remote connect instead: a launch
    /// fetch would surprise the phone's holder with an authorization
    /// out of nowhere.
    internal func start() {
      #if os(macOS)
        startFetch()
      #endif
    }

    #if os(macOS)
      private func startFetch() {
        guard !isRunning, Self.needsIdentity else { return }
        isRunning = true
        Task.detached(priority: .userInitiated) {
          let certificateDER: Data?
          do {
            let response = try RappPersistentRequesterClient(
              displayName: "ReFineID Mac"
            ).perform(.readAuthenticationCertificate)
            guard case .authenticationCertificate(let certificate) = response else {
              await Self.shared.finish(nil)
              return
            }
            certificateDER = certificate
          } catch {
            certificateDER = nil
          }
          await Self.shared.finish(certificateDER)
        }
      }

      private func finish(_ certificateDER: Data?) {
        defer { isRunning = false }
        guard let certificateDER else { return }
        Self.publish(certificateDER)
      }
    #endif

  }
#endif
