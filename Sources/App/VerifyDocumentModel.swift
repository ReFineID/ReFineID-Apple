// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import Foundation
  import Observation

  /// Verifies one chosen signed document and holds its report.
  ///
  /// The verdict itself is computed offline; when the network answers,
  /// each signer's revocation is additionally checked against fresh
  /// OCSP or CRL evidence and the row states which basis it reached.
  @MainActor
  @Observable
  internal final class VerifyDocumentModel {
    /// The revocation basis one signature's row reached.
    internal enum Revocation: Sendable, Equatable {
      case checking
      case good(Date)
      case revoked
      case unavailable
    }

    /// One signature's report with its revocation basis.
    internal struct SignatureRow: Identifiable, Sendable {
      internal let id: Int
      internal let report: DocumentVerification.SignatureReport
      internal var revocation: Revocation
    }

    internal enum Phase {
      case idle
      case verifying
      case report([SignatureRow], documentTimestampedAt: [Date])
      case failed(String)
    }

    private static var unreadableMessage: String {
      String(localized: "The document could not be read.")
    }

    internal private(set) var phase = Phase.idle

    /// The verified file's name, for the report heading.
    internal private(set) var documentName = ""

    private static func message(
      for failure: DocumentVerification.Failure
    ) -> String {
      switch failure {
      case .notAPdf:
        String(localized: "The file is not a PDF.")
      case .unreadable:
        Self.unreadableMessage
      case .noSignatures:
        String(localized: "The document carries no signatures.")
      case .unsupportedProfile:
        String(localized: "The signature profile is not supported.")
      }
    }

    private static func liveRevocation(
      of report: DocumentVerification.SignatureReport
    ) async -> Revocation {
      guard
        let issuer = report.issuerCertificate,
        let facts = CertificateFacts(der: report.signerCertificate)
      else {
        return .unavailable
      }
      do {
        _ = try await ValidationMaterialCollector.status(
          of: report.signerCertificate,
          facts: facts,
          under: issuer,
          at: Date(),
          dependencies: .live
        )
        return .good(Date())
      } catch is AuthenticatedRevocation {
        return .revoked
      } catch {
        return .unavailable
      }
    }

    /// Verifies the document at one picked location.
    internal func verify(url: URL) {
      if case .verifying = phase { return }
      phase = .verifying
      documentName = url.lastPathComponent
      Task.detached(priority: .userInitiated) { [weak self] in
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
          if scoped { url.stopAccessingSecurityScopedResource() }
        }
        guard let document = try? Data(contentsOf: url) else {
          await self?.finish(.failed(Self.unreadableMessage))
          return
        }
        do {
          let report = try DocumentVerification.verify(document: document)
          let rows = report.signatures.enumerated().map { index, signature in
            SignatureRow(id: index, report: signature, revocation: .checking)
          }
          await self?.finish(
            .report(rows, documentTimestampedAt: report.documentTimestampedAt))
          await self?.checkRevocation(of: rows)
        } catch let failure as DocumentVerification.Failure {
          await self?.finish(.failed(Self.message(for: failure)))
        } catch {
          await self?.finish(.failed(Self.unreadableMessage))
        }
      }
    }

    /// Returns the screen to the picker.
    internal func reset() {
      phase = .idle
      documentName = ""
    }

    private func finish(_ phase: Phase) {
      self.phase = phase
    }

    /// Upgrades each row from checking to a live revocation basis.
    private func checkRevocation(of rows: [SignatureRow]) async {
      for row in rows {
        let outcome = await Self.liveRevocation(of: row.report)
        guard case .report(var current, let stamped) = phase else { return }
        guard let index = current.firstIndex(where: { $0.id == row.id })
        else { continue }
        current[index].revocation = outcome
        phase = .report(current, documentTimestampedAt: stamped)
      }
    }

  }

#endif
