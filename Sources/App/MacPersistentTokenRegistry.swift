// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import Security

  /// Fetches the public authentication certificate once and publishes it as a
  /// per-user persistent CryptoTokenKit identity. Private-key operations stay
  /// delegated to the iPhone relay.
  @MainActor
  internal final class MacPersistentTokenRegistry {
    internal static let shared = MacPersistentTokenRegistry()
    private var isRunning = false

    private init() {}

    internal func start() {
      guard !isRunning, Self.needsIdentity else { return }
      isRunning = true
      Task.detached(priority: .userInitiated) {
        let certificateDER: Data?
        do {
          let response = try RappPersistentRequesterClient(
            displayName: "ReFineID Mac"
          ).perform(.readAuthenticationCertificate)
          guard case let .authenticationCertificate(certificate) = response else {
            await MacPersistentTokenRegistry.shared.finish(nil)
            return
          }
          certificateDER = certificate
        } catch {
          certificateDER = nil
        }
        await MacPersistentTokenRegistry.shared.finish(certificateDER)
      }
    }

    private func finish(_ certificateDER: Data?) {
      defer { isRunning = false }
      guard let certificateDER else { return }
      Self.publish(certificateDER)
    }

    private static var driverConfiguration: TKTokenDriver.Configuration? {
      TKTokenDriver.Configuration.driverConfigurations[
        PersistentTokenIdentity.classID
      ]
    }

    private static var needsIdentity: Bool {
      driverConfiguration?.tokenConfigurations.isEmpty ?? true
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

      let instanceID = "iphone-nfc-" + SHA256.hash(data: certificateDER)
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
  }
#endif
