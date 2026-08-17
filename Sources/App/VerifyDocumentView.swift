// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import SwiftUI
  import UniformTypeIdentifiers

  /// Verifies a chosen signed PDF and reports each signature's facts.
  internal struct VerifyDocumentView: View {
    @State private var model = VerifyDocumentModel()
    @State private var importing = false

    internal var body: some View {
      Form {
        switch model.phase {
        case .idle:
          chooseSection
        case .verifying:
          Section {
            ProgressView(String(localized: "Verifying"))
              .frame(maxWidth: .infinity)
          }
        case .report(let rows, let documentTimestampedAt):
          reportSections(rows, documentTimestampedAt: documentTimestampedAt)
        case .failed(let message):
          Section {
            CredentialOutcomeText(message: message, tone: .failure)
          }
          chooseSection
        }
      }
      .navigationTitle(
        String(
          localized: "verify.title",
          defaultValue: "Verify",
          table: "DocumentSigning")
      )
      .fileImporter(
        isPresented: $importing,
        allowedContentTypes: [.pdf]
      ) { result in
        if case .success(let url) = result {
          model.verify(url: url)
        }
      }
    }

    private var chooseSection: some View {
      Section {
        Button(String(localized: "Choose a signed document")) {
          importing = true
        }
        .accessibilityIdentifier("verifyChooseDocument")
      }
    }

    @ViewBuilder
    private func reportSections(
      _ rows: [VerifyDocumentModel.SignatureRow],
      documentTimestampedAt: [Date]
    ) -> some View {
      Section {
        LabeledContent(String(localized: "Document")) {
          Text(model.documentName)
            .multilineTextAlignment(.trailing)
        }
        ForEach(documentTimestampedAt, id: \.self) { stamped in
          LabeledContent(String(localized: "Document timestamp")) {
            HStack {
              Text(stamped.formatted(date: .abbreviated, time: .shortened))
              CredentialValidationIndicator(valid: true)
            }
          }
        }
      }
      ForEach(rows) { row in
        signatureSection(row)
      }
      Section {
        Button(String(localized: "Verify another document")) {
          model.reset()
          importing = true
        }
        .accessibilityIdentifier("verifyAnotherDocument")
      }
    }

    private func signatureSection(
      _ row: VerifyDocumentModel.SignatureRow
    ) -> some View {
      Section {
        LabeledContent {
          Text(holder(of: row.report))
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("verifySigner")
        } label: {
          PersonRowLabel(configured: row.report.isValid)
        }
        factRow(
          String(localized: "Document intact"),
          holds: row.report.documentIntact
        )
        factRow(
          String(localized: "Signature"),
          holds: row.report.signatureValid
        )
        factRow(
          String(localized: "Certificate chain"),
          holds: row.report.chainVerified
        )
        timestampRow(row.report)
        revocationRow(row.revocation)
      } header: {
        Text(String(localized: "Signature"))
          .frame(maxWidth: .infinity, alignment: .leading)
          .listRowInsets(EdgeInsets())
      }
    }

    private func holder(
      of report: DocumentVerification.SignatureReport
    ) -> String {
      report.signerIdentifier.isEmpty
        ? report.signerName
        : "\(report.signerName) \(report.signerIdentifier)"
    }

    private func factRow(_ name: String, holds: Bool) -> some View {
      LabeledContent(name) {
        CredentialValidationIndicator(valid: holds)
      }
    }

    private func timestampRow(
      _ report: DocumentVerification.SignatureReport
    ) -> some View {
      LabeledContent(String(localized: "Timestamp")) {
        HStack {
          if let timestampedAt = report.timestampedAt {
            Text(
              timestampedAt.formatted(
                date: .abbreviated, time: .shortened)
            )
          }
          CredentialValidationIndicator(valid: report.timestampsValid)
        }
      }
    }

    private func revocationRow(
      _ revocation: VerifyDocumentModel.Revocation
    ) -> some View {
      LabeledContent(String(localized: "Revocation")) {
        switch revocation {
        case .checking:
          ProgressView()
        case .good(let checkedAt):
          HStack {
            Text(
              checkedAt.formatted(date: .omitted, time: .shortened)
            )
            CredentialValidationIndicator(valid: true)
          }
        case .revoked:
          CredentialValidationIndicator(valid: false)
        case .unavailable:
          Text(String(localized: "Not checked"))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

#endif
