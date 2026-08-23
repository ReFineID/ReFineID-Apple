// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

import CardCore
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

internal struct RappPairingButton: View {
    @Binding internal var isPresented: Bool
    @State private var hasSelectedPair = false

    internal var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: hasSelectedPair ? "link" : "link.badge.plus")
                .replacingSymbolPlainly()
        }
        .accessibilityLabel(String(localized: "Remote"))
        .accessibilityValue(
            hasSelectedPair ? "Paired device selected" : "No paired device selected"
        )
        .task(id: isPresented) {
            let catalog = RappPairCatalog(vault: RappDeviceVault())
            hasSelectedPair = (try? await catalog.selectedPair()) != nil
        }
    }
}
#endif
