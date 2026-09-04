// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// Hosts the one credentials surface and the reader identity model
  /// that lights up its reader states.
  internal struct ReaderIdentityRootView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @StateObject private var model = ReaderIdentityModeModel()
    @StateObject private var remoteModel = RemoteCardModel()
    @ObservedObject private var authorizationInbox = RappAuthorizationInbox.shared

    internal var body: some View {
      NavigationStack {
        CardCredentialsView(
          readerModel: model,
          remoteModel: remoteModel
        )
      }
      .onAppear {
        model.refresh()
        remoteModel.refresh()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappPairingModel.pairingsDidChangeNotification)
      ) { _ in
        remoteModel.refresh()
      }
      .onValueChange(of: scenePhase) { _ in
        if scenePhase == .active {
          model.refresh()
          remoteModel.refresh()
        }
      }
      .sheet(
        isPresented: Binding(
          get: { authorizationInbox.request != nil },
          set: { shown in
            guard !shown, let pending = authorizationInbox.request else { return }
            authorizationInbox.deny(pending.requestID)
          }
        )
      ) {
        if let request = authorizationInbox.request {
          RappAuthorizationView(
            request: request,
            inbox: authorizationInbox
          )
          .presentationDetents([.medium, .large])
        }
      }
    }
  }

#endif
