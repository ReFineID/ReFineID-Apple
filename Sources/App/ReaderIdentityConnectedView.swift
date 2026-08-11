//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
#if os(iOS)

  import SwiftUI

  /// The transport-state UI while attached readers own ReFineID identity.
  internal struct ReaderIdentityConnectedView: View {
    /// Breathing room around the deliberately minimal reader message.
    private static let messagePadding: CGFloat = 32

    internal let model: ReaderIdentityModeModel

    internal var body: some View {
      Text(message)
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)
        .padding(Self.messagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("ReFineID")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Distinguishes one usable reader from several without exposing card data.
    private var message: String {
      if model.liveReaderTokenCount == 1 {
        "USB-C reader connected with Finnish ID card."
      } else {
        "USB-C readers connected with Finnish ID cards."
      }
    }
  }

#endif
