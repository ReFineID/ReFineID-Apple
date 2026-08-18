// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoTokenKit

extension TKSmartCardTokenSession {
  /// The card this request runs against, with its exclusive session already
  /// open and the application selected.
  ///
  /// The 26 systems replaced the `smartCard` property with
  /// `getSmartCardWithError:`. Both hand back the same card in the same
  /// state; the documentation of the replacement repeats the property's
  /// word for word. Which spelling compiles without a deprecation depends
  /// on the deployment target, and the two platforms here do not share one:
  /// macOS builds against 26, where the property is deprecated, while iOS
  /// builds against 16, where the replacement does not yet exist. So each
  /// asks in the terms its own target accepts.
  internal func requestedSmartCard() throws -> TKSmartCard {
    #if os(macOS)
      return try getSmartCard()
    #else
      return smartCard
    #endif
  }
}
