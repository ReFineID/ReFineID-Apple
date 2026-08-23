// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The application settings, separated by the choice they affect.
  internal struct ReFineIDSettingsView: View {
    private enum Pane: Hashable {
      #if FEATURE_CONTACTLESS
        case cards
      #endif
      #if FEATURE_PDF_STAMP
        case pdfStamp
      #endif
      case pin
      #if REFINEID_REMOTE_CARD
        case remote
      #endif
      case timeStamp
    }

    private static let paneWidth: CGFloat = 680
    private static let paneHeight: CGFloat = 300

    #if REFINEID_REMOTE_CARD
      @State private var pane = Pane.remote
    #else
      @State private var pane = Pane.pin
    #endif

    internal var body: some View {
      TabView(selection: $pane) {
        featureSettingsTabs
        mainSettingsTabs
      }
      .frame(minWidth: Self.paneWidth, minHeight: Self.paneHeight)
    }

    @ViewBuilder private var featureSettingsTabs: some View {
      #if FEATURE_CONTACTLESS
        CardReadingSettingsView()
          .tabItem {
            Label(String(localized: "Cards"), systemImage: "creditcard")
          }
          .tag(Pane.cards)
      #endif
      #if FEATURE_PDF_STAMP
        DocumentStampSettingsView()
          .tabItem {
            Label(String(localized: "PDF Stamp"), systemImage: "signature")
          }
          .tag(Pane.pdfStamp)
      #endif
    }

    @ViewBuilder private var mainSettingsTabs: some View {
      CardManagementView()
        .tabItem {
          Label(String(localized: "PIN"), systemImage: "key")
        }
        .tag(Pane.pin)
      #if REFINEID_REMOTE_CARD
        RemotePairingSettingsView()
          .tabItem {
            Label(String(localized: "Remote"), systemImage: "key.radiowaves.forward")
          }
          .tag(Pane.remote)
      #endif
      TimestampAuthoritiesSettingsView()
        .tabItem {
          Label(String(localized: "Time Stamp"), systemImage: "clock.badge.checkmark")
        }
        .tag(Pane.timeStamp)
    }
  }

#endif
