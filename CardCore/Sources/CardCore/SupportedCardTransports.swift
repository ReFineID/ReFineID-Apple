/// What the running platform can actually do, independent of what the
/// holder has chosen.
///
/// This is the ceiling every stored preference is clamped to. It is a
/// build-time fact, not a setting: macOS has no NFC smart-card slot API
/// at all (`createNFCSlot` is `API_UNAVAILABLE(macos)`), and on iOS the
/// NFC slot arrived in version 26.
public enum SupportedCardTransports {
  /// The transports this build can offer on this device.
  public static var current: CardTransportSelection {
    #if canImport(CoreNFC)
      if #available(iOS 26.0, *) {
        return .all
      }
      return .readerOnly
    #else
      return .readerOnly
    #endif
  }

  /// Whether the holder can be offered a near-field choice at all.
  ///
  /// When false the settings UI hides the near-field control rather than
  /// showing a disabled one: a Mac has no antenna to switch on.
  public static var offersNearField: Bool {
    current.permits(.nearField)
  }
}
