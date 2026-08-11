// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
#if os(macOS)

  import SwiftUI

  /// The application settings, separated by the choice they affect.
  internal struct ReFineIDSettingsView: View {
    private static let paneWidth: CGFloat = 680
    private static let paneHeight: CGFloat = 300

    internal var body: some View {
      TabView {
        #if FEATURE_CONTACTLESS
          CardReadingSettingsView()
            .tabItem {
              Label("Cards", systemImage: "creditcard")
            }
        #endif
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
