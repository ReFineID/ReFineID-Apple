#if os(iOS)

  import SwiftUI

  /// Chooses the app's only useful surface while a USB-C reader identity is live.
  internal struct ReaderIdentityRootView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @State private var model = ReaderIdentityModeModel()

    internal var body: some View {
      NavigationStack {
        if model.isActive {
          ReaderIdentityConnectedView(model: model)
        } else {
          CardCredentialsView()
        }
      }
      .onAppear { model.refresh() }
      .onChange(of: scenePhase) {
        if scenePhase == .active {
          model.refresh()
        }
      }
    }
  }

#endif
