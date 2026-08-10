#if os(macOS)

  import SwiftUI

  /// The application settings, separated by the choice they affect.
  internal struct ReFineIDSettingsView: View {
    private static let paneWidth: CGFloat = 680
    private static let paneHeight: CGFloat = 300

    internal var body: some View {
      TabView {
        #if FEATURE_PDF_STAMP
          DocumentStampSettingsView()
            .tabItem {
              Label("PDF Stamp", systemImage: "signature")
            }
        #endif
        TimestampAuthoritiesSettingsView()
          .tabItem {
            Label("Time Stamps", systemImage: "clock.badge.checkmark")
          }
      }
      .frame(minWidth: Self.paneWidth, minHeight: Self.paneHeight)
    }
  }

#endif
