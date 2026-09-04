// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import CryptoKit
  import Foundation

  /// Holds an active near-field session briefly so consecutive authentication
  /// requests in the same page or TLS renegotiation burst execute without
  /// re-prompting the user.
  internal actor RappNearFieldSessionHolder {
    internal struct Context: Sendable {
      internal let isPin1Authenticated: Bool
      internal let isRoleProbed: @Sendable (CredentialRole) -> Bool
      internal let isNegativePin: @Sendable (String) -> Bool
      internal let markPin1Authenticated: @Sendable () -> Void
      internal let markRoleProbed: @Sendable (CredentialRole) -> Void
      internal let recordNegativePin: @Sendable (String) -> Void
    }

    internal static let shared = RappNearFieldSessionHolder()

    private static let burstGracePeriodSeconds: Double = 1.2

    private var activeSession: NearFieldCardSession?
    private var expirationTask: Task<Void, Never>?
    private var isPin1Authenticated = false
    private var probedRoles = Set<CredentialRole>()
    private var negativePinFingerprints = Set<Data>()

    internal func registerNegativePin(_ digits: String) {
      let hash = Data(SHA256.hash(data: Data(digits.utf8)))
      negativePinFingerprints.insert(hash)
    }

    internal func setPin1Authenticated(_ value: Bool) {
      isPin1Authenticated = value
    }

    internal func insertProbedRole(_ role: CredentialRole) {
      probedRoles.insert(role)
    }

    internal func execute(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      expirationTask?.cancel()
      expirationTask = nil

      guard let currentSession = await obtainSession(message: message) else {
        return nil
      }

      let context = makeContext()
      let result = await performWithSession(
        currentSession,
        cardAccessNumber: cardAccessNumber,
        context: context,
        operation: operation
      )
      scheduleExpiration(succeeded: result != nil)
      return result
    }

    internal func closeSession() {
      activeSession?.end()
      activeSession = nil
      expirationTask?.cancel()
      expirationTask = nil
      isPin1Authenticated = false
      probedRoles.removeAll()
    }

    private func obtainSession(message: String) async -> NearFieldCardSession? {
      if let existing = activeSession { return existing }
      do {
        let session = try await NearFieldCardSession.open(message: message)
        activeSession = session
        isPin1Authenticated = false
        probedRoles.removeAll()
        return session
      } catch {
        closeSession()
        return nil
      }
    }

    private func makeContext() -> Context {
      let currentPin1Auth = isPin1Authenticated
      let currentProbed = probedRoles
      let negativeSet = negativePinFingerprints

      return Context(
        isPin1Authenticated: currentPin1Auth,
        isRoleProbed: { role in currentProbed.contains(role) },
        isNegativePin: { digits in
          let hash = Data(SHA256.hash(data: Data(digits.utf8)))
          return negativeSet.contains(hash)
        },
        markPin1Authenticated: { [weak self] in
          Task { await self?.setPin1Authenticated(true) }
        },
        markRoleProbed: { [weak self] role in
          Task { await self?.insertProbedRole(role) }
        },
        recordNegativePin: { [weak self] digits in
          Task { await self?.registerNegativePin(digits) }
        }
      )
    }

    private func performWithSession(
      _ session: NearFieldCardSession,
      cardAccessNumber: String,
      context: Context,
      operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? session.withCardSession { channel -> RappCardExecutor.Outcome? in
            guard
              let operations = CardMaintenance.selectedOperations(
                over: channel,
                cardAccessNumber: cardAccessNumber
              )
            else {
              return nil
            }
            return operation(operations, context)
          }
          continuation.resume(returning: answer.flatMap(\.self))
        }
      }
    }

    private func scheduleExpiration(succeeded: Bool) {
      if !succeeded {
        closeSession()
        return
      }
      expirationTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(Self.burstGracePeriodSeconds))
        if !Task.isCancelled {
          await self?.closeSession()
        }
      }
    }
  }
#endif
