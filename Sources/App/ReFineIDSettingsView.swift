// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The application settings, separated by the choice they affect.
  ///
  /// PIN and Time Stamp operate on a local card, so those tabs exist
  /// only while a card is in a reader. Remote stays in the middle slot
  /// whether they are there or not: inserting a card fills PIN on its
  /// leading side and Time Stamp on its trailing side, without moving
  /// Remote.
  internal struct ReFineIDSettingsView: View {
    private enum Pane: Hashable {
      case cards
      case pdfStamp
      case pin
      case remote
      case timeStamp
    }

    private enum Layout {
      static let paneWidth: CGFloat = 680
      static let paneHeight: CGFloat = 300
      static let tabSpacing: CGFloat = 12
      static let tabSlotWidth: CGFloat = 84
      static let tabSlotHeight: CGFloat = 52
      static let tabCornerRadius: CGFloat = 8
      static let tabBarTopPadding: CGFloat = 10
      static let tabBarBottomPadding: CGFloat = 8
      static let tabLabelSpacing: CGFloat = 2
    }

    /// Where Settings lands when a local card is not in a reader.
    private static var paneWithoutLocalCard: Pane {
      #if REFINEID_REMOTE_CARD
        .remote
      #elseif FEATURE_PDF_STAMP
        .pdfStamp
      #elseif FEATURE_CONTACTLESS
        .cards
      #else
        .pin
      #endif
    }

    @ObservedObject private var cardPresence = CardPresence.shared
    #if REFINEID_REMOTE_CARD
      @State private var pane = Pane.remote
    #else
      @State private var pane = Pane.pin
    #endif

    private var hasLocalCard: Bool {
      cardPresence.isCardPresent
    }

    /// The pane the window may actually show for the current card.
    private var displayedPane: Pane {
      switch pane {
      case .pin, .timeStamp:
        hasLocalCard ? pane : Self.paneWithoutLocalCard

      default:
        pane
      }
    }

    internal var body: some View {
      VStack(spacing: 0) {
        tabBar
        Divider()
        paneBody
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .frame(minWidth: Layout.paneWidth, minHeight: Layout.paneHeight)
      .onChange(of: hasLocalCard) { _, present in
        if !present {
          pane = Self.paneWithoutLocalCard
        }
      }
    }

    private var tabBar: some View {
      HStack {
        Spacer(minLength: 0)
        tabItems
        Spacer(minLength: 0)
      }
      .padding(.top, Layout.tabBarTopPadding)
      .padding(.bottom, Layout.tabBarBottomPadding)
    }

    private var tabItems: some View {
      HStack(spacing: Layout.tabSpacing) {
        extraFeatureTabs
        tabButton(
          pane: .pin,
          title: String(localized: "PIN"),
          systemImage: "key",
          visible: hasLocalCard
        )
        remoteTab
        tabButton(
          pane: .timeStamp,
          title: String(localized: "Time Stamp"),
          systemImage: "clock.badge.checkmark",
          visible: hasLocalCard
        )
      }
    }

    @ViewBuilder private var extraFeatureTabs: some View {
      #if FEATURE_CONTACTLESS
        tabButton(
          pane: .cards,
          title: String(localized: "Cards"),
          systemImage: "creditcard",
          visible: true
        )
      #endif
      #if FEATURE_PDF_STAMP
        tabButton(
          pane: .pdfStamp,
          title: String(localized: "PDF Stamp"),
          systemImage: "signature",
          visible: true
        )
      #endif
    }

    @ViewBuilder private var remoteTab: some View {
      #if REFINEID_REMOTE_CARD
        tabButton(
          pane: .remote,
          title: String(localized: "Remote"),
          systemImage: "key.radiowaves.forward",
          visible: true
        )
      #else
        Color.clear
          .frame(width: Layout.tabSlotWidth, height: Layout.tabSlotHeight)
      #endif
    }

    @ViewBuilder private var paneBody: some View {
      switch displayedPane {
      #if FEATURE_CONTACTLESS
        case .cards:
          CardReadingSettingsView()
      #endif
      #if FEATURE_PDF_STAMP
        case .pdfStamp:
          DocumentStampSettingsView()
      #endif
      case .pin:
        if hasLocalCard {
          CardManagementView()
        }
      #if REFINEID_REMOTE_CARD
        case .remote:
          RemotePairingSettingsView()
      #endif
      case .timeStamp:
        if hasLocalCard {
          TimestampAuthoritiesSettingsView()
        }
      default:
        EmptyView()
      }
    }

    private func tabButton(
      pane: Pane,
      title: String,
      systemImage: String,
      visible: Bool
    ) -> some View {
      Group {
        if visible {
          Button {
            self.pane = pane
          } label: {
            VStack(spacing: Layout.tabLabelSpacing) {
              Image(systemName: systemImage)
                .font(.title2)
              Text(title)
                .font(.caption)
            }
            .frame(width: Layout.tabSlotWidth, height: Layout.tabSlotHeight)
            .foregroundStyle(displayedPane == pane ? Color.accentColor : Color.secondary)
            .background {
              if displayedPane == pane {
                RoundedRectangle(cornerRadius: Layout.tabCornerRadius)
                  .fill(.quaternary)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(title))
          .accessibilityAddTraits(displayedPane == pane ? .isSelected : [])
        } else {
          Color.clear
            .frame(width: Layout.tabSlotWidth, height: Layout.tabSlotHeight)
            .accessibilityHidden(true)
        }
      }
    }
  }

#endif
