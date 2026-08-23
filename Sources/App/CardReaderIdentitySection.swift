// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import SwiftUI

  /// The identity area for cards in an attached reader.
  ///
  /// The same Person row NFC uses once an identity exists. A reader
  /// already named the holder, so CAN and PIN 1 do not appear here.
  internal struct CardReaderIdentitySection: View {
    internal let holders: [String]

    internal var body: some View {
      Section {
        if holders.isEmpty {
          ProgressView()
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
          ForEach(holders, id: \.self) { holder in
            LabeledContent {
              Text(holder)
                .textSelection(.enabled)
                .accessibilityIdentifier("readerCardHolder")
            } label: {
              PersonRowLabel(configured: true)
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
