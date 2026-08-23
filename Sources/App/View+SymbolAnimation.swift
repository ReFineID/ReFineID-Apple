// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// Symbol animations that a system older than the effects can still render.
///
/// The app runs on systems either side of the symbol-effect APIs, so each
/// helper applies the effect where it exists and returns the view untouched
/// where it does not. A symbol that cannot animate still shows every state
/// it would otherwise animate between.
///
/// The branches stay structurally identical -- one modifier or none on the
/// same view -- so a symbol keeps its identity and its animation state.
extension View {
    /// Pulses the symbol once whenever the value changes.
    @ViewBuilder
    internal func pulsingSymbol(value: some Equatable) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            symbolEffect(.pulse, value: value)
        } else {
            self
        }
    }

    /// Bounces the symbol repeatedly until the value changes.
    @ViewBuilder
    internal func bouncingSymbol(value: some Equatable) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            symbolEffect(.bounce, options: .repeating, value: value)
        } else {
            self
        }
    }

    /// Replaces one symbol with another in place.
    ///
    /// The magic replacement carries layers across the change where the
    /// system provides it, and falls back to the upward slide elsewhere.
    @ViewBuilder
    internal func replacingSymbol() -> some View {
        #if os(iOS) && !REFINEID_IOS_FLOOR_26
        if #available(iOS 18.0, *) {
            contentTransition(
                .symbolEffect(
                    .replace.magic(fallback: .offUp.byLayer),
                    options: .nonRepeating)
            )
        } else if #available(iOS 17.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
        #else
        contentTransition(
            .symbolEffect(
                .replace.magic(fallback: .offUp.byLayer),
                options: .nonRepeating)
        )
        #endif
    }

    /// Replaces one symbol with another without the layered fallback.
    @ViewBuilder
    internal func replacingSymbolPlainly() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}
