// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_REMOTE_CARD

import UIKit

/// Lifts the screen while a code is being scanned, and puts it back.
///
/// A camera reads dark modules against a light field, and a dimmed screen
/// narrows that difference until the code stops resolving. The screen is
/// the light source here, so it is turned up for as long as the code is
/// shown and returned to whatever the holder had afterwards.
@MainActor
internal enum ScreenBrightness {
    /// What the holder had before the code took the screen.
    private static var previous: CGFloat?

    /// Bright enough to read in a lit room without being unpleasant.
    private static let scanningLevel: CGFloat = 1.0

    /// Raises the screen and remembers what to put back.
    internal static func raiseForScanning() {
        guard previous == nil else { return }
        previous = UIScreen.main.brightness
        UIScreen.main.brightness = scanningLevel
    }

    /// Returns the screen to the level the holder chose.
    internal static func restore() {
        guard let previous else { return }
        UIScreen.main.brightness = previous
        Self.previous = nil
    }
}

#endif
