// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@_spi(TokenExtension)
import CardCore
import CryptoTokenKit
import Foundation
import Security

/// Generic persistent-token principal selected by the extension plist.
///
/// The direct smart-card driver remains a separate extension on every
/// platform; this driver owns only the delegated persistent identity.
internal final class PersistentTokenDriver: TKTokenDriver,
                                            TKTokenDriverDelegate {
    private final class PersistentToken: TKToken, TKTokenDelegate {
        fileprivate let certificate: SecCertificate
        fileprivate let publicKey: SecKey
        fileprivate let profile: CardKeyProfile

        fileprivate init(
            tokenDriver: TKTokenDriver,
            configuration: TKToken.Configuration
        ) throws {
            let item = try configuration.certificate(
                for: PersistentTokenIdentity.certificateObjectID
            )
            guard
                let parsedCertificate = SecCertificateCreateWithData(nil, item.data as CFData),
                let parsedPublicKey = SecCertificateCopyKey(parsedCertificate),
                let resolvedProfile = CardKeyProfile.resolve(fromPublicKey: parsedPublicKey)
            else {
                throw TKError(.corruptedData)
            }
            self.certificate = parsedCertificate
            self.publicKey = parsedPublicKey
            self.profile = resolvedProfile
            super.init(tokenDriver: tokenDriver, instanceID: configuration.instanceID)
            delegate = self
        }

        /// The @objc delegate requirement fixes the throwing signature even
        /// though this implementation cannot fail.
        fileprivate func createSession(  // swiftlint:disable:this unneeded_throws_rethrows
            _: TKToken
        ) -> TKTokenSession {
            PersistentTokenSession(token: self)
        }
    }

    private final class PersistentTokenSession: TKTokenSession,
                                                TKTokenSessionDelegate {
        /// The requesting surface named on the authorizer's approval sheet.
        private static var displayContext: String {
            #if os(macOS)
            "macOS CryptoTokenKit"
            #else
            "iOS CryptoTokenKit"
            #endif
        }

        /// Milliseconds in one second, for the ages this token reports.
        private static let millisecondsPerSecond = 1_000.0

        private let persistentToken: PersistentToken

        fileprivate init(token: PersistentToken) {
            persistentToken = token
            super.init(token: token)
            delegate = self
        }

        /// Records what this token did with a browser's request.
        ///
        /// A signature the card made and this token refuses is the one failure
        /// that leaves no trace anywhere: the browser is told only that the
        /// data was corrupt, asks again, and is refused again.
        /// How long ago, in whole milliseconds.
        private static func millisecondsSince(_ started: Date) -> Int {
            Int(Date().timeIntervalSince(started) * Self.millisecondsPerSecond)
        }

        private static func say(_ line: String) {
            #if DEBUG
            ExtensionTrace.record(line)
            ExtensionTrace.flush()
            #endif
        }

        fileprivate func tokenSession(
            _: TKTokenSession,
            supports operation: TKTokenOperation,
            keyObjectID: Any,
            algorithm: TKTokenKeyAlgorithm
        ) -> Bool {
            let supported =
                operation == .signData
                && (keyObjectID as? String) == PersistentTokenIdentity.keyObjectID
                && SigningAlgorithmResolver.advertises(
                    algorithm,
                    profile: persistentToken.profile
                )
            #if DEBUG
            print(
                """
          [PersistentTokenDriver] supports: op=\(operation.rawValue) \
          algo=\(SigningAlgorithmResolver.describe(algorithm)) \
          profile=\(String(describing: persistentToken.profile)) -> \(supported)
          """
            )
            fflush(stdout)
            #endif
            return supported
        }

        fileprivate func tokenSession(
            _: TKTokenSession,
            sign dataToSign: Data,
            keyObjectID: Any,
            algorithm: TKTokenKeyAlgorithm
        ) throws -> Data {
            guard
                (keyObjectID as? String) == PersistentTokenIdentity.keyObjectID,
                let request = SigningAlgorithmResolver.resolve(
                    algorithm,
                    input: dataToSign,
                    profile: persistentToken.profile
                )
            else {
                throw TKError(.notImplemented)
            }

            guard
                let relayAlgorithm = RappOperationDriver.SignatureAlgorithm(
                    request.algorithm
                )
            else {
                throw TKError(.notImplemented)
            }
            let started = Date()
            Self.say("rapp sign asked")
            let signature: Data
            do {
                let response = try RappPersistentRequesterClient(
                    displayName: "ReFineID Token"
                ).perform(
                    .browserAuthentication(
                        displayContext: Self.displayContext,
                        keyProfile: RappOperationDriver.KeyProfile(persistentToken.profile),
                        algorithm: relayAlgorithm,
                        digest: request.digest
                    )
                )
                guard case .signature(let receivedSignature) = response else {
                    throw RappRequesterClientError.unexpectedResult
                }
                signature = receivedSignature
            } catch {
                // CryptoTokenKit carries one code back to the caller, so the reason
                // the relay gave is lost at this boundary. It is the only account
                // of why a browser was refused an identity, so it is recorded
                // before the throw narrows it to a communication failure.
                #if DEBUG
                ExtensionTrace.record(
                    "rapp sign failed after \(Self.millisecondsSince(started)) ms:"
                        + " \(String(describing: error))")
                ExtensionTrace.flush()
                #endif
                throw TKError(.communicationError)
            }
            guard request.isSatisfied(by: signature, from: persistentToken.publicKey) else {
                Self.say("rapp sign rejected after \(Self.millisecondsSince(started)) ms")
                throw TKError(.corruptedData)
            }
            Self.say("rapp sign served after \(Self.millisecondsSince(started)) ms")
            return signature
        }
    }

    override internal init() {
        super.init()
        delegate = self
    }

    internal func tokenDriver(
        _: TKTokenDriver,
        tokenFor configuration: TKToken.Configuration
    ) throws -> TKToken {
        try PersistentToken(tokenDriver: self, configuration: configuration)
    }
}
