// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// A device that reads its own card hosts the credentials surface below.
// One that cannot has a screen of its own, in `RequesterIdentityView`.
#if os(iOS) && REFINEID_LOCAL_CARD

  import SwiftUI

  /// Hosts the one credentials surface and the reader identity model
  /// that lights up its reader states.
  internal struct ReaderIdentityRootView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @StateObject private var model = ReaderIdentityModeModel()
    @StateObject private var remoteModel = RemoteCardModel()

    @ObservedObject private var authorizationInbox = RappAuthorizationInbox.shared
    @State private var showsRappPairing = false

    internal var body: some View {
      NavigationStack {
        CardCredentialsView(
          readerModel: model,
          remoteModel: remoteModel,
          openRemoteReader: { showsRappPairing = true }
        )
      }
      .onAppear {
        model.refresh()
        remoteModel.refresh()
      }
      .onValueChange(of: scenePhase) { _ in
        if scenePhase == .active {
          model.refresh()
          remoteModel.refresh()
        }
      }
      .onValueChange(of: authorizationInbox.request?.id) { _ in
        // One presenter can hold one sheet: a pending authorization takes
        // the stage from the pairing sheet.
        if authorizationInbox.request != nil {
          showsRappPairing = false
        }
      }
      .sheet(
        isPresented: $showsRappPairing,
        onDismiss: { remoteModel.refresh() }
      ) {
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
