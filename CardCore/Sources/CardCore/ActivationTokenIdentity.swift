// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// Identifies the empty CryptoTokenKit token published for a
  /// recognized card that still needs its factory credentials changed.
  ///
  /// It deliberately carries no keychain items. Its presence is only
  /// the extension's authoritative, event-driven answer to the app;
  /// an unactivated card must never be exposed as a usable identity.
  public enum ActivationTokenIdentity {
    public static let instancePrefix = "activation-required-"

    public static func instanceID(forSlotNamed slotName: String) -> String {
      let encoded =
        slotName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "reader"
      return instancePrefix + encoded
    }

    public static func recognizes(tokenID: String) -> Bool {
      tokenID.contains(":" + instancePrefix)
    }
  }

#endif
