// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

import SwiftUI

/// The application settings, separated by the choice they affect.
internal struct ReFineIDSettingsView: View {
    private static let paneWidth: CGFloat = 680
    private static let paneHeight: CGFloat = 300

    internal var body: some View {
        TabView {
            #if FEATURE_CONTACTLESS
            CardReadingSettingsView()
                .tabItem {
                    Label("Cards", systemImage: "creditcard")
                }
            #endif
            #if FEATURE_PDF_STAMP
            DocumentStampSettingsView()
                .tabItem {
                    Label("PDF Stamp", systemImage: "signature")
                }
            #endif
            // Credential management is settings work: rarely visited,
            // never part of signing a document, and a card is asked for
            // only once a task runs. It lived in a window of its own
            // opened from a button on the main screen, which gave the
            // rarest task the most permanent button in the app.
            CardManagementView()
                .tabItem {
                    Label("PIN", systemImage: "key")
                }
            TimestampAuthoritiesSettingsView()
                .tabItem {
                    Label("Time Stamp", systemImage: "clock.badge.checkmark")
                }
        }
        .frame(minWidth: Self.paneWidth, minHeight: Self.paneHeight)
    }
}

#endif
