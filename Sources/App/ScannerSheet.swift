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

#if os(iOS)

  import SwiftUI

  /// The camera, framed so it can be dismissed, with its light control.
  internal struct ScannerSheet: View {
    @Binding internal var torchEnabled: Bool
    @Binding internal var isScanning: Bool

    /// Receives the scanned digits before the sheet dismisses itself.
    internal let complete: (String) -> Void

    internal var body: some View {
      NavigationStack {
        CardAccessNumberScanner(
          torchEnabled: $torchEnabled
        ) { digits in
          torchEnabled = false
          complete(digits)
          isScanning = false
        }
        .ignoresSafeArea()
        .navigationTitle("Scan card QR code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
      }
      .onDisappear {
        torchEnabled = false
      }
    }

    /// Dismissal and light controls kept above the live preview.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          torchEnabled = false
          isScanning = false
        }
      }
      if CardAccessNumberScanner.hasTorch {
        ToolbarItem(placement: .primaryAction) {
          Button {
            torchEnabled.toggle()
          } label: {
            Label(
              torchEnabled ? "Turn light off" : "Turn light on",
              systemImage: torchEnabled
                ? "flashlight.on.fill" : "flashlight.off.fill")
          }
          .accessibilityIdentifier("cardAccessNumberScannerTorch")
        }
      }
    }
  }

#endif
