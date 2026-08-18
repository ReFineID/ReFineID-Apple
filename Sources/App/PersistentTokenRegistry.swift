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
      guard shared.isRunning == false else { return }
      publish(certificateDER)
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
