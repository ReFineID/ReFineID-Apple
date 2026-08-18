#if os(iOS)

  import Foundation

  internal func virtualCardLocalized(
    _ key: StaticString,
    defaultValue: String.LocalizationValue
  ) -> String {
    VirtualIDCardOverlayLocalization.localizedText(
      key,
      defaultValue: defaultValue)
  }

#endif
