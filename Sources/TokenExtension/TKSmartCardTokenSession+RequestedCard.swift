// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoTokenKit

#if !os(macOS) && !REFINEID_IOS_FLOOR_26
  /// The pre-26 spelling of the request's card.
  ///
  /// The `smartCard` property is deprecated on the 26 systems, and the
  /// diagnostic follows the deployment floor. Reading it through a
  /// protocol requirement it witnesses names no deprecated declaration
  /// at the use site, which is what lets the floor-16 configurations
  /// compile it without the warning their gates treat as an error.
  private protocol RequestedCardBySmartCardProperty {
    var smartCard: TKSmartCard { get }
  }

  extension TKSmartCardTokenSession: RequestedCardBySmartCardProperty {}
#endif

extension TKSmartCardTokenSession {
  /// The card this request runs against, with its exclusive session already
  /// open and the application selected.
  ///
  /// The 26 systems replaced the `smartCard` property with
  /// `getSmartCardWithError:`. Both hand back the same card in the same
  /// state; the documentation of the replacement repeats the property's
  /// word for word. Which spelling compiles without a deprecation depends
  /// on the deployment floor, and iOS no longer has one floor: Debug and
  /// Profile build at 16, the shipping configurations at 26
  /// (Version.xcconfig). So each floor asks in the terms it accepts.
  internal func requestedSmartCard() throws -> TKSmartCard {
    #if os(macOS) || REFINEID_IOS_FLOOR_26
      return try getSmartCard()
    #else
      return (self as RequestedCardBySmartCardProperty).smartCard
    #endif
  }
}
