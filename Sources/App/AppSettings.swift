// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

import Foundation

/// The keys the app's runtime settings live under, in one place so a
/// window and the Settings pane bind the same stored value.
///
/// `UserDefaults`-backed through `@AppStorage`; a change in Settings
/// reaches every window that reads the key.
internal enum AppSettings {
    /// Whether contactless cards are served: the CAN entry appears and
    /// numbers are offered only when this is on.
    ///
    /// Off by default. Contactless is the rare case - a card presented
    /// on the antenna rather than inserted - and the holder who wants
    /// it turns it on in Settings; contact readers need no setting.
    internal static let contactlessEnabled = "contactlessEnabled"
}

#endif
