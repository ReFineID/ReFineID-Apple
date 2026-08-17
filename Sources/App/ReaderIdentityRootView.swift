// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// Chooses the app's only useful surface while a reader identity is live.
  internal struct ReaderIdentityRootView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @State private var model = ReaderIdentityModeModel()

    @State private var authorizationInbox = RappAuthorizationInbox.shared
    @State private var showsRappPairing = false

    internal var body: some View {
      NavigationStack {
        if model.isActive {
          ReaderIdentityConnectedView(model: model)
        } else {
          CardCredentialsView()
        }
      }
      .onAppear {
        model.refresh()
      }
      .onChange(of: scenePhase) {
        if scenePhase == .active {
          model.refresh()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          RappPairingButton(isPresented: $showsRappPairing)
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
