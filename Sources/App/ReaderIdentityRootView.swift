// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// Hosts the one credentials surface and the reader identity model
  /// that lights up its reader states.
  internal struct ReaderIdentityRootView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @State private var model = ReaderIdentityModeModel()

    @State private var authorizationInbox = RappAuthorizationInbox.shared
    @State private var showsRappPairing = false

    internal var body: some View {
      NavigationStack {
        CardCredentialsView(
          readerModel: model,
          openRemoteReader: { showsRappPairing = true }
        )
      }
      .onAppear {
        model.refresh()
      }
      .onChange(of: scenePhase) {
        if scenePhase == .active {
          model.refresh()
        }
      }
      .sheet(isPresented: $showsRappPairing) {
        RappPairingView()
      }
      .sheet(
        item: Binding(
          get: { authorizationInbox.request },
          set: { presented in
            guard
              presented == nil,
              let pending = authorizationInbox.request
            else { return }
            authorizationInbox.deny(pending.id)
          }
        )
      ) { request in
        RappAuthorizationView(
          request: request,
          inbox: authorizationInbox
        )
        .presentationDetents([.medium, .large])
      }
    }
  }

#endif
