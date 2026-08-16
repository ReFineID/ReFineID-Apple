// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(ReFineIDRapp)
  import Foundation
  import ReFineIDRapp

  extension RappDeviceVault: RappPairVault {
    public func insertDeviceOnly(pairId: Data, record: Data) throws {
      do {
        try insertPair(pairID: pairId, record: record)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func loadDeviceOnly(pairId: Data) throws -> Data? {
      do {
        return try loadPair(pairID: pairId)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func revokeDeviceOnly(pairId: Data, revokedAtMs: UInt64) throws {
      do {
        try revokePair(pairID: pairId, revokedAtMilliseconds: revokedAtMs)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func isRevoked(pairId: Data) throws -> Bool {
      do {
        return try pairIsRevoked(pairID: pairId)
      } catch {
        throw rappVaultError(error)
      }
    }
  }

  extension RappDeviceVault: RappOperationVault {
    public func persistRequester(
      pairId: Data,
      operationId: Data,
      record: Data
    ) throws {
      do {
        try persistRequester(pairID: pairId, operationID: operationId, record: record)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func loadRequester(pairId: Data) throws -> [Data] {
      do {
        return try loadRequester(pairID: pairId)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func persistProxy(
      pairId: Data,
      operationId: Data,
      record: Data
    ) throws {
      do {
        try persistProxy(pairID: pairId, operationID: operationId, record: record)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func persistProxyResult(
      pairId: Data,
      operationId: Data,
      record: Data,
      result: Data
    ) throws {
      do {
        try persistProxyResult(
          pairID: pairId,
          operationID: operationId,
          record: record,
          result: result)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func retainProxyUncertain(
      pairId: Data,
      operationId: Data,
      record: Data
    ) throws {
      do {
        try retainProxyUncertain(pairID: pairId, operationID: operationId, record: record)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func acknowledgeProxyResult(
      pairId: Data,
      operationId: Data,
      record: Data
    ) throws {
      do {
        try acknowledgeProxyResult(pairID: pairId, operationID: operationId, record: record)
      } catch {
        throw rappVaultError(error)
      }
    }

    public func loadProxy(pairId: Data) throws -> [RappStoredProxyJournal] {
      do {
        return try loadProxy(pairID: pairId).map { stored in
          RappStoredProxyJournal(
            record: stored.record,
            retainedResult: stored.retainedResult)
        }
      } catch {
        throw rappVaultError(error)
      }
    }
  }

  private func rappVaultError(_ error: any Error) -> RappVaultError {
    guard let failure = error as? RappDeviceVault.Failure else {
      return .Unavailable
    }
    switch failure {
    case .duplicate:
      return .IdentifierAlreadyUsed
    case .notFound:
      return .PairNotFound
    case .malformed, .unavailable:
      return .Unavailable
    }
  }
#endif
