// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// Hosts the one credentials surface and the reader identity model
  /// that lights up its reader states.
  internal struct ReaderIdentityRootView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @StateObject private var model = ReaderIdentityModeModel()

    #if REFINEID_REMOTE_CARD
      @StateObject private var remoteModel = RemoteCardModel()

      @ObservedObject private var authorizationInbox = RappAuthorizationInbox.shared
    #endif

    internal var body: some View {
      #if REFINEID_REMOTE_CARD
        remoteCapableBody
      #else
        NavigationStack {
          CardCredentialsView(readerModel: model)
        }
        .onAppear {
          model.refresh()
        }
        .onValueChange(of: scenePhase) { _ in
          if scenePhase == .active {
            model.refresh()
          }
        }
      #endif
    }

    #if REFINEID_REMOTE_CARD
      private var remoteCapableBody: some View {
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
        .onValueChange(of: scenePhase) { _ in
          if scenePhase == .active {
            model.refresh()
            remoteModel.refresh()
          }
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
    #endif
  }

#endif
