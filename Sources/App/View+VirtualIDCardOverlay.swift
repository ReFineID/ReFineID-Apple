#if os(iOS)

  import SwiftUI

  /// Form rows must grow with Dynamic Type instead of retaining the compact
  /// one-line text-field height. One shared treatment keeps every editable
  /// virtual-card value usable under the same accessibility settings.
  extension View {
    private static let fieldLineLimitRange = 1...2
    private static let menuLineLimitRange = 1...3

    fileprivate func virtualCardEditorField() -> some View {
      lineLimit(Self.fieldLineLimitRange)
        .fixedSize(horizontal: false, vertical: true)
    }

    fileprivate func virtualCardMenuControl() -> some View {
      lineLimit(Self.menuLineLimitRange)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

#endif
