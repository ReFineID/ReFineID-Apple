// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
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
    internal static let shared = PersistentTokenRegistry()

    private static var driverConfiguration: TKTokenDriver.Configuration? {
      TKTokenDriver.Configuration.driverConfigurations[
        PersistentTokenIdentity.classID
      ]
    }

    private static var needsIdentity: Bool {
      driverConfiguration?.tokenConfigurations.isEmpty ?? true
    }
    private var isRunning = false

    private init() {
      // The one instance is `shared`; nothing is set up per instance.
    }

    /// Publishes an already-fetched certificate as the persistent
    /// identity.
    internal static func publish(certificateDER: Data) {
      guard shared.isRunning == false else { return }
      publish(certificateDER)
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

    private static func publish(_ certificateDER: Data) {
      guard
        let driver = driverConfiguration,
        let certificate = SecCertificateCreateWithData(
          nil,
          certificateDER as CFData
        ),
        CardKeyProfile.resolve(fromCertificate: certificate) != nil,
        let certificateItem = TKTokenKeychainCertificate(
          certificate: certificate,
          objectID: PersistentTokenIdentity.certificateObjectID
        ),
        let keyItem = TKTokenKeychainKey(
          certificate: certificate,
          objectID: PersistentTokenIdentity.keyObjectID
        )
      else {
        return
      }

      let instanceID =
        "iphone-nfc-"
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
      configuration.keychainItems = [certificateItem, keyItem]
      #if DEBUG
        print("[persistent-token] published \(instanceID)")
        fflush(stdout)
      #endif
    }

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
