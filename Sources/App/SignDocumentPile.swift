// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import SwiftUI

  /// The documents waiting to be signed: every one named, every one
  /// removable.
  ///
  /// A name and a count names one file and hides the rest, so a wrong
  /// file in the pile cannot be seen, and taking it out means emptying
  /// the pile and dropping everything again. Each document is listed
  /// with the icon the Finder gives it and carries its own removal.
  ///
  /// The removals are drawn at all times rather than on hover: they
  /// are the only way out of a pile short of clearing it, and a
  /// control that has to be discovered by moving a pointer over a row
  /// cannot be reached from the keyboard at all.
  internal struct SignDocumentPile: View {
    /// Every file waiting, in the order it will be carried.
    internal let documents: [URL]

    /// The shape the pile will take, which decides what is said about
    /// it: one container between them, or one signature each.
    internal let format: SignatureFormat

    /// Takes one document out of the pile.
    internal let remove: (URL) -> Void

    /// Adds more documents to the pile.
    internal let add: () -> Void

    /// Empties it.
    internal let clear: () -> Void

    private static let rowSpacing: CGFloat = 8
    private static let rowPadding: CGFloat = 5
    private static let footerSpacing: CGFloat = 6

    /// The document icon, at the size a form row carries.
    @ScaledMetric(relativeTo: .body)
    private var iconSide: CGFloat = 16

    /// Past this the list scrolls instead of growing the window, which
    /// a pile of any size would otherwise push off the screen.
    @ScaledMetric(relativeTo: .body)
    private var maximumListHeight: CGFloat = 132

    internal var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(documents.enumerated()), id: \.element) { index, document in
              if index > 0 {
                Divider()
              }
              row(for: document)
            }
          }
        }
        .frame(maxHeight: maximumListHeight)
        .accessibilityLabel("Documents to sign")
        footer
      }
    }

    /// One document: what it is, what it is called, and its way out.
    private func row(for document: URL) -> some View {
      HStack(spacing: Self.rowSpacing) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: document.path))
          .resizable()
          .frame(width: iconSide, height: iconSide)
          .accessibilityHidden(true)
        // Shortened in the middle so both ends stay readable. The whole
        // name is still what VoiceOver reads and what the pointer
        // uncovers, so no window size loses which file is being signed.
        Text(document.lastPathComponent)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(document.path)
          .accessibilityLabel(document.lastPathComponent)
        Spacer(minLength: Self.rowSpacing)
        Button {
          remove(document)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove \(document.lastPathComponent)")
        .help("Remove \(document.lastPathComponent)")
      }
      .padding(.vertical, Self.rowPadding)
    }

    /// What the pile becomes, and the two ways to change it.
    private var footer: some View {
      VStack(alignment: .leading, spacing: Self.footerSpacing) {
        Divider()
        HStack {
          if let summary = Self.summary(of: documents, format: format) {
            Text(summary)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Add…", action: add)
            .buttonStyle(.link)
            .accessibilityIdentifier("signChooseDocument")
          Button("Clear", action: clear)
            .buttonStyle(.link)
        }
      }
      .padding(.top, Self.footerSpacing)
    }

    /// What a pile of more than one becomes, said only when there is
    /// more than one: a single row already says everything about
    /// itself.
    internal static func summary(
      of documents: [URL],
      format: SignatureFormat
    ) -> String? {
      guard documents.count > 1 else { return nil }
      return format == .pades
        ? String(localized: "\(documents.count) documents, each signed separately")
        : String(localized: "\(documents.count) documents in one container")
    }
  }

#endif
