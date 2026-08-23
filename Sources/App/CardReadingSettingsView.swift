// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

import SwiftUI

/// The card-reading choices: how a card is presented to the Mac.
internal struct CardReadingSettingsView: View {
    @AppStorage(AppSettings.contactlessEnabled)
    private var contactlessEnabled = false

    internal var body: some View {
        Form {
            Section {
                Toggle("Contactless (NFC) cards", isOn: $contactlessEnabled)
                Text(
                    """
            Off, a card is read only when inserted into a reader. On, a \
            card presented on a contactless reader is opened with the \
            access number printed on its face.
            """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#endif
