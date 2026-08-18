#if os(iOS)

  import SwiftUI

  /// Form rows must grow with Dynamic Type instead of retaining the compact
  /// one-line text-field height. One shared treatment keeps every editable
  /// virtual-card value usable under the same accessibility settings.
  /// Line-limit ranges for the editable rows, at file scope because a
  /// protocol extension cannot hold stored statics.
  private enum LineLimits {
    static let field = 1...2
    static let menu = 1...3
  }

  extension View {

    internal func virtualCardEditorField() -> some View {
      lineLimit(LineLimits.field)
        .fixedSize(horizontal: false, vertical: true)
    }

    internal func virtualCardMenuControl() -> some View {
      lineLimit(LineLimits.menu)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

#endif
