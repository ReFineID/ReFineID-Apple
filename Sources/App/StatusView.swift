// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import SwiftUI
  import UniformTypeIdentifiers

  /// The Mac window: whether the card can log you in, and signing a
  /// document with it.
  ///
  /// It stays small. The login row does zero card I/O - it reads only
  /// what `ctkd` has already published. Once that identity is ready, the
  /// health key starts one short retry-counter probe. It never polls and
  /// never delays identity presentation or signing controls.
  ///
  /// Signing lives here rather than in a window of its own: dropping a
  /// document on the app is the thing a holder will try, and the app
  /// they dropped it on should be the one that signs it.
  internal struct StatusView: View {
    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 24
    private static let dropHeight: CGFloat = 96
    private static let dropCornerRadius: CGFloat = 10
    private static let dropBorderWidth: CGFloat = 2

    /// The narrowest the window may be, which grows with the text
    /// inside it so a larger size widens the window instead of
    /// wrapping every label in it.
    @ScaledMetric(relativeTo: .body)
    private var minimumWidth: CGFloat = 420

    internal let model = LoginIdentityModel.shared
    @ObservedObject internal var retryHealth = CredentialRetryHealth.shared
    @ObservedObject internal var cardPresence = CardPresence.shared
    #if REFINEID_REMOTE_CARD
      internal let remoteRegistry = PersistentTokenRegistry.shared
    #endif
    @State private var signing = SignDocumentModel()

    /// Notices a card waiting to be taken into use, and carries the
    /// model its activation form works through.
    @State private var activation = ActivationWatch()
    @State private var pin2Cache = Pin2Cache()
    @State private var offeringNumber = false
    @State private var pin2 = ""
    @State private var accessNumber = ""
    @State private var isTargeted = false
    @State private var format = SignatureFormat.pades
    @FocusState private var pinFocused: Bool

    #if FEATURE_CONTACTLESS
      /// Whether the holder has enabled contactless card reading.
      @AppStorage(AppSettings.contactlessEnabled)
      private var contactlessEnabled = false
    #endif

    /// The signing state, readable by the split-out outcome section.
    internal var signingModel: SignDocumentModel { signing }

    /// Ready when a document is waiting and a PIN 2 is available -
    /// either freshly entered, or remembered from a signature within
    /// the last minute.
    private var canSign: Bool {
      signing.pending != nil
        && (!asksLocalPin2 || Self.isEntryComplete(pin2) || pin2Cache.isWarm)
        && !signing.working
        // Not while the card is being read for the stamp: it is one
        // card, and asking it to sign mid-read is asking it to be in
        // two places.
        && !signing.readingStamp
    }

    /// Whether an unready card is provably on a contactless
    /// interface, which is the one state that asks for an access
    /// number.
    private var awaitingAccessNumber: Bool {
      #if FEATURE_CONTACTLESS
        contactlessEnabled
          && availability == .cardWithoutIdentity
          && cardPresence.isContactlessCardPresent
      #else
        false
      #endif
    }

    internal var body: some View {
      VStack(alignment: .leading, spacing: Self.spacing) {
        HStack {
          Text(verbatim: "RefineID")
            .font(.largeTitle.bold())
          Spacer()
          if !cardPresence.isReaderConnected {
            SettingsLink {
              StatusSettingsGlyph(
                pinLevel: retryHealth.level,
                routeAvailable: availability == .ready
              )
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityIdentifier("manageCard")
          }
        }
        Form {
          // While an entered number awaits the card's verdict, the
          // window is the instruction and nothing else: the steps to
          // take are the only thing to say, and a drop target or a
          // PIN window cannot be used before the card can.
          if offeringNumber || awaitingAccessNumber {
            // Only the access number when one is needed: no identity
            // row to overload, no drop target and no PIN window that
            // cannot be used before the card can. The section itself
            // compiles in with its feature, and outside the flow it
            // appears only when the slot's answer proves the card is
            // on the antenna - a contact card is never asked.
            SealedCardSection(offering: $offeringNumber)
          } else if activation.awaitsActivation {
            // The extension's activation token is the authoritative
            // semantic result. It outranks derived token readiness and
            // publishes no identity or signing keys.
            CardActivationSection(
              model: activation.management
            ) { model.refresh() }
            CardOutcomeSection(model: activation.management)
          } else if availability == .ready {
            // Signing belongs exclusively to a published identity. No
            // provisional or error state offers unusable controls.
            LabeledContent("Person") {
              IdentityStateView(
                availability: availability,
                warnsUnavailableCard: false
              )
            }
            .accessibilityIdentifier("loginIdentityStatus")
            documentSection
            signatureSection
            outcomeSection
          } else if activation.isReading {
            // Protocol negotiation may momentarily make the reader say
            // its slot is empty. The operation is still in progress,
            // so neither a removal message nor signing controls belong
            // in this state.
            LabeledContent("Person") {
              IdentityStateView(
                availability: .cardWithoutIdentity,
                warnsUnavailableCard: false
              )
            }
            .accessibilityIdentifier("loginIdentityStatus")
          } else if availability == .noCard {
            // With no card there is exactly one thing to say, and a
            // labeled row saying it twice is not it.
            #if REFINEID_REMOTE_CARD
              if !cardPresence.isReaderConnected {
                RemotePairingPromptView()
              } else {
                Text("Insert your identity card into the reader")
                  .foregroundStyle(.secondary)
                  .accessibilityIdentifier("loginIdentityStatus")
              }
            #else
              Text("Insert your identity card into the reader")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("loginIdentityStatus")
            #endif
          } else {
            // A card with no usable identity cannot sign. Keep the
            // failure local to the identity row instead of offering
            // controls whose operation must fail.
            LabeledContent("Person") {
              IdentityStateView(
                availability: availability,
                warnsUnavailableCard: activation.warnsUnavailableCard
              )
            }
            .accessibilityIdentifier("loginIdentityStatus")
          }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(Self.padding)
      .frame(minWidth: minimumWidth, alignment: .leading)
      // Nothing entered in an earlier run may serve this one: a number
      // left behind is withdrawn before the card could use it, so
      // every launch starts with none. Only with the feature: without
      // it no number is ever offered, and touching the group container
      // to clean up would be the one thing that creates it.
      #if FEATURE_CONTACTLESS
        .task { SealedCardSection.withdrawOfferedNumber() }
      #endif
      .onAppear {
        model.refresh()
        react(to: availability)
        activation.observe(
          availability: availability,
          paused: offeringNumber || awaitingAccessNumber,
          identity: model
        )
        #if DEBUG
          if DebugSampleDocuments.isEnabled(), signing.queued.isEmpty {
            _ = accept(DebugSampleDocuments.seeded())
          }
        #endif
      }
      .onChange(of: availability) { _, now in
        react(to: now)
        activation.observe(
          availability: now,
          paused: offeringNumber || awaitingAccessNumber,
          identity: model
        )
      }
      .onChange(of: offeringNumber || awaitingAccessNumber) { _, _ in
        activation.observe(
          availability: availability,
          paused: offeringNumber || awaitingAccessNumber,
          identity: model
        )
      }
      .onChange(of: activation.defersRemoval) { wasDeferred, isDeferred in
        guard wasDeferred, !isDeferred, availability == .noCard else { return }
        react(to: .noCard)
      }
      .onDisappear { activation.stop() }
      // Signing is what this window is for, and its answer arrived in
      // silence: focus stays on Sign, and the outcome is drawn below it.
      .announcesOutcome(signing.failure)
      .announcesOutcome(signing.notice)
      .announcesOutcome(activation.management.failure)
      .announcesOutcome(activation.management.notice)
    }

    /// The documents to sign: dropped, or chosen.
    @ViewBuilder private var documentSection: some View {
      Section {
        dropContents
          .frame(maxWidth: .infinity)
          .contentShape(.rect)
          .overlay {
            if isTargeted {
              RoundedRectangle(cornerRadius: Self.dropCornerRadius)
                .strokeBorder(.tint, lineWidth: Self.dropBorderWidth)
            }
          }
          .dropDestination(for: URL.self) { urls, _ in
            accept(urls)
          } isTargeted: { targeted in
            isTargeted = targeted
          }
          .accessibilityLabel("Documents to sign")
          .accessibilityValue(Self.pileValue(signing.queued))
      }
    }

    /// What the drop area shows: an invitation, or the pile itself.
    ///
    /// The invitation keeps the tall target a drop needs. The pile
    /// replaces it, because a list of files is the drop target once
    /// there are files, and holding both would put a stack of names
    /// under an icon inviting a stack of names.
    @ViewBuilder private var dropContents: some View {
      if signing.queued.isEmpty {
        SignDropInvitation(targeted: isTargeted) { choose() }
          .frame(maxWidth: .infinity, minHeight: Self.dropHeight)
      } else {
        SignDocumentPile(
          documents: signing.queued,
          remove: { document in
            signing.remove(document)
            // The shape follows what is left: taking the one
            // spreadsheet out of a pile of PDFs makes PAdES possible
            // again, and leaving ASiC-E chosen would hide that.
            format = Self.sharedFormat(for: signing.queued)
          },
          add: { choose() },
          clear: { signing.clear() }
        )
      }
    }

    /// PIN2, the optional stamp, and the action - shown once a
    /// document is waiting.
    @ViewBuilder private var signatureSection: some View {
      if signing.pending != nil {
        let pinTitle =
          pin2Cache.isWarm ? String(localized: "PIN 2 (remembered)") : String(localized: "PIN 2")
        Section {
          SignatureFormatRow(documents: signing.queued, format: $format)
          if asksLocalPin2 {
            CredentialSecretField(
              name: pinTitle,
              text: $pin2,
              revealIdentifier: "signPin2Reveal"
            ) {
              SecureField(pinTitle, text: $pin2)
                .onChange(of: pin2) { _, typed in
                  pin2 = LimitedDigits.pin(typed)
                }
                .focused($pinFocused)
                .onSubmit { sign() }
                .accessibilityIdentifier("signPin2")
            }
          }
          // Stamp is drawn into the signed PDF revision only.
          #if FEATURE_PDF_STAMP
            if format == .pades {
              StampRow(signing: signing, accessNumber: $accessNumber)
            }
          #endif
          #if DEBUG
            if DebugRevokedDocumentSigning.isEnabled() {
              Text(DebugRevokedDocumentSigning.armedWarning)
                .foregroundStyle(.orange)
            }
          #endif
          actionRow
        }
        .onAppear { if asksLocalPin2 { pinFocused = true } }
      }
    }

    /// The action row, carrying the progress too: it is already there
    /// and half empty, and a line that appears and disappears steps
    /// the window as the card is read.
    @ViewBuilder private var actionRow: some View {
      HStack {
        if let note = Self.progressNote(signing) {
          ProgressView().controlSize(.small)
          Text(note)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Sign…") { sign() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(!canSign)
          .accessibilityIdentifier("signDocument")
      }
    }

    /// Ready stands recovery down and a removed card resets its budget.
    ///
    /// The activation watch owns the unready path so inspection and
    /// recovery remain serialized.
    private func react(to availability: LoginIdentityModel.Availability) {
      switch availability {
      case .ready:
        model.cancelRecovery(cardLeft: false)
        offeringNumber = false
        retryHealth.refreshFromReader()

      case .cardWithoutIdentity:
        retryHealth.clear()

      case .noCard:
        // A CCID protocol reset can publish this between T=Any and its
        // successful T=0/T=1 fallback. Defer removal cleanup until the
        // card operation itself has ended.
        guard !activation.defersRemoval else { return }
        retryHealth.clear()
        model.cancelRecovery(cardLeft: true)
        signing.cardRemoved()
        pin2 = ""
        accessNumber = ""
        // A card that left takes the remembered PIN with it: the next
        // card, even the same one re-inserted, re-earns the memory.
        pin2Cache.clear()
      // The offered access number deliberately survives this state:
      // a contactless card leaves the field between taps, and the
      // offer exists to serve the next tap. Withdrawing it here once
      // deleted the number in the moment between lifting the card
      // and laying it back, so the mint it was typed for read
      // nothing. Launch and quit are where it is withdrawn.
      }
    }

    /// Takes a dropped document of any type: a PDF is signed in place
    /// by default, anything else travels in an ASiC-E container.
    ///
    /// The shape is decided by the whole pile and not by what just
    /// arrived. Dropping one PDF onto a spreadsheet already waiting
    /// would otherwise leave PAdES chosen for a set that cannot take
    /// it, and the card would be asked before the spreadsheet refused.
    private func accept(_ urls: [URL]) -> Bool {
      guard !urls.isEmpty else { return false }
      signing.accept(urls)
      format = Self.sharedFormat(for: signing.queued)
      pin2 = ""
      pinFocused = true
      return true
    }

    /// Opens the chooser, which may pick several documents to pile.
    private func choose() {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = true
      guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
      _ = accept(panel.urls)
    }

    /// Asks where the signature goes, then signs.
    ///
    /// The panel runs here, from the button, and not inside the signing
    /// task: a modal panel raised from an async function blocks the
    /// main actor SwiftUI draws on, and a panel that never appears
    /// looks exactly like a button that does nothing.
    private func sign() {
      guard canSign, let source = signing.pending else { return }
      // Several documents take one container between them, so they ask
      // for one file. Several PDFs each keep their own signature
      // inside themselves, so those still ask for a folder.
      let several = signing.queued.count > 1
      let separately = several && format == .pades
      let folder =
        separately
        ? SignedOutput.chooseFolder(startingAt: source.deletingLastPathComponent())
        : nil
      let destination =
        separately ? nil : SignedOutput.chooseFile(for: signing.queued, format: format)
      guard separately ? folder != nil : destination != nil else { return }
      let entry = Self.isEntryComplete(pin2) ? pin2 : (pin2Cache.current() ?? "")
      if asksLocalPin2, entry.isEmpty { return }
      pin2 = ""
      let number = accessNumber
      let chosenFormat = format
      signing.beginAction()
      Task {
        if let folder {
          await signing.signAll(
            pin2: entry, accessNumber: number, format: chosenFormat, intoDirectory: folder
          )
        } else if let destination {
          if several {
            await signing.signTogether(pin2: entry, to: destination)
          } else {
            await signing.sign(
              pin2: entry, accessNumber: number, format: chosenFormat, to: destination
            )
          }
        }
        // Remember only a PIN a signature accepted, so a remembered
        // value is always known good and never spends an attempt; any
        // failure forgets it and asks for the PIN again.
        if signing.lastActionSignedSomething {
          if asksLocalPin2 { pin2Cache.remember(entry) }
          signing.clearQueue()
        } else if asksLocalPin2 {
          pin2Cache.clear()
        }
      }
    }

    // PIN 2 for a paired phone is collected on that phone, not here.
    // It is not stored in the iPhone app. The phone holds it in memory
    // for at most one minute so a pile of documents is one prompt.
    // A local reader still collects PIN 2 in this window.
    // The Mac does not send PIN 2.
  }

#endif
