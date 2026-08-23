// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
import CardCore
import SwiftUI

/// The identity area for cards in an attached reader.
internal struct CardReaderIdentitySection: View {
    internal let holders: [String]
    internal let hasPin1: Bool
    internal let onForgetPin1: () -> Void
    internal let onSavePin1: (String) async -> String?

    @State private var pin1Entry = ""
    @State private var isVerifying = false
    @State private var failureMessage: String?
    @FocusState private var isPin1Focused: Bool

    private var isPin1EntryComplete: Bool {
        pin1Entry.count >= Pin1.minimumDigitCount
            && pin1Entry.count <= Pin1.maximumDigitCount
    }

    internal var body: some View {
        Group {
            identitySection
            if !hasPin1 {
                authSection
                if let failureMessage {
                    Section {
                        CredentialOutcomeText(message: failureMessage, tone: .failure)
                    }
                }
            }
        }
    }

    private var identitySection: some View {
        Section {
            if holders.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(holders, id: \.self) { holder in
                    HStack {
                        LabeledContent {
                            Text(holder)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("readerCardHolder")
                        } label: {
                            PersonRowLabel(configured: true)
                        }
                        if hasPin1 {
                            Spacer(minLength: 0)
                            Button(role: .destructive, action: onForgetPin1) {
                                Image(systemName: "minus.circle")
                                    .font(.title3)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Forget PIN 1"))
                            .accessibilityIdentifier("forgetReaderPin1")
                        }
                    }
                }
            }
        } header: {
            Text("Identity")
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets())
        }
    }

    private var authSection: some View {
        Section {
            CredentialSecretField(
                name: String(localized: "Basic Code (PIN 1)"),
                text: $pin1Entry,
                revealIdentifier: "readerPin1Reveal"
            ) {
                SecureField("Basic Code (PIN 1)", text: $pin1Entry)
                    .font(.body)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isPin1Focused)
                    .accessibilityIdentifier("readerPin1Field")
                    .onValueChange(of: pin1Entry) { typed in
                        pin1Entry = LimitedDigits.pin1(typed)
                    }
            }

            Button {
                savePin1()
            } label: {
                BrowserAuthenticationEnableLabel()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isPin1EntryComplete || isVerifying)
            .accessibilityIdentifier("saveReaderPin1")
        } header: {
            Text("Browser authentication")
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets())
        }
    }

    private func savePin1() {
        guard isPin1EntryComplete, !isVerifying else { return }
        let entered = pin1Entry
        isVerifying = true
        failureMessage = nil
        Task {
            let failure = await onSavePin1(entered)
            await MainActor.run {
                isVerifying = false
                if let failure {
                    failureMessage = failure
                } else {
                    pin1Entry = ""
                    isPin1Focused = false
                }
            }
        }
    }
}
#endif
