// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS) && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation

  /// Holds an active near-field session briefly so consecutive authentication
  /// requests in the same page or TLS renegotiation burst execute without
  /// re-prompting the user.
  internal actor RappNearFieldSessionHolder {
    internal static let shared = RappNearFieldSessionHolder()

    private static let burstGracePeriodSeconds: Double = 3.5

    private var activeSession: NearFieldCardSession?
    private var expirationTask: Task<Void, Never>?

    internal func execute(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      expirationTask?.cancel()
      expirationTask = nil

      var session = activeSession
      if session == nil {
        do {
          session = try await NearFieldCardSession.open(message: message)
          activeSession = session
        } catch {
          activeSession = nil
          return nil
        }
      }

      guard let currentSession = session else { return nil }

      let result: RappCardExecutor.Outcome? = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? currentSession.withCardSession { channel -> RappCardExecutor.Outcome? in
            guard
              let operations = CardMaintenance.selectedOperations(
                over: channel,
                cardAccessNumber: cardAccessNumber
              )
            else {
              return nil
            }
            return operation(operations)
          }
          continuation.resume(returning: answer.flatMap(\.self))
        }
      }

      if result == nil {
        currentSession.end()
        activeSession = nil
      } else {
        expirationTask = Task { [weak self] in
          try? await Task.sleep(for: .seconds(Self.burstGracePeriodSeconds))
          if !Task.isCancelled {
            await self?.closeSession()
          }
        }
      }

      return result
    }

    internal func closeSession() {
      activeSession?.end()
      activeSession = nil
      expirationTask?.cancel()
      expirationTask = nil
    }
  }
#endif
