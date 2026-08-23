// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import SwiftUI

  /// The identity area for cards in an attached reader.
  ///
  /// The same Person row NFC uses once an identity exists. A reader
  /// already named the holder, so CAN and PIN 1 do not appear here.
  internal struct CardReaderIdentitySection: View {
    /// The minimum comfortable tap target.
    private static let tapTargetSide: CGFloat = 44

    /// Minimum gap between the holder name and the forget control.
    private static let forgetButtonGap: CGFloat = 4

    internal let holders: [String]
    internal let onForgetPin1: () -> Void

    internal var body: some View {
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
              Spacer(minLength: Self.forgetButtonGap)
              Button(role: .destructive, action: onForgetPin1) {
                Image(systemName: "minus.circle")
                  .font(.title3)
                  .foregroundStyle(.red)
              }
              .buttonStyle(.borderless)
              .frame(width: Self.tapTargetSide, height: Self.tapTargetSide)
              .contentShape(Rectangle())
              .accessibilityLabel(Text("Forget PIN 1"))
              .accessibilityIdentifier("forgetReaderPin1")
            }
          }
        }
      } header: {
        Text("Identity")
          .frame(maxWidth: .infinity, alignment: .leading)
          .listRowInsets(EdgeInsets())
      }
    }
  }
#endif
