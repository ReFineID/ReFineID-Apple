// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import SwiftUI

/// One compact validation result shared by card credential forms.
internal struct CredentialValidationIndicator: View {
  internal let valid: Bool
  internal var entriesDiffer = false
  internal var unchanged = false
  internal var isEmpty = false

  internal var body: some View {
    Image(systemName: symbol)
      .foregroundStyle(color)
      .opacity(isEmpty ? 0 : 1)
      .accessibilityHidden(isEmpty)
      .accessibilityLabel(Text(accessibilityDescription))
  }

  private var symbol: String {
    if valid { return "checkmark.circle.fill" }
    return hasWarning ? "exclamationmark.triangle.fill" : "xmark.circle.fill"
  }

  private var color: Color {
    if valid { return .green }
    return hasWarning ? .orange : .red
  }

  private var hasWarning: Bool {
    entriesDiffer || unchanged
  }

  private var accessibilityDescription: String {
    if valid { return String(localized: "Valid entry") }
    if unchanged {
      return String(localized: "The new PIN must differ from the current PIN.")
    }
    if entriesDiffer { return String(localized: "The new entries differ.") }
    return String(localized: "Invalid entry")
  }
}

/// A secret card-code row with one consistent, accessible reveal control.
///
/// The editable control remains a `SecureField` while its digits are shown.
/// The visible value is a non-interactive overlay, so revealing a PIN does
/// not turn it into selectable or copyable plain text. The eye remains an
/// editing aid, while validation is the final result at the end of the row.
internal struct CredentialSecretField<Field: View, Validation: View>: View {
  private let name: String
  @Binding private var text: String
  private let revealIdentifier: String
  private let field: () -> Field
  private let validation: () -> Validation
  @State private var revealsValue = false

  internal init(
    name: String,
    text: Binding<String>,
    revealIdentifier: String,
    @ViewBuilder field: @escaping () -> Field,
    @ViewBuilder validation: @escaping () -> Validation
  ) {
    self.name = name
    self._text = text
    self.revealIdentifier = revealIdentifier
    self.field = field
    self.validation = validation
  }

  internal var body: some View {
    HStack {
      field()
        .foregroundStyle(revealsValue && !text.isEmpty ? Color.clear : Color.primary)
        .overlay(alignment: .leading) {
          if revealsValue && !text.isEmpty {
            Text(verbatim: text)
              .foregroundStyle(.primary)
              .lineLimit(1)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
      Button {
        revealsValue.toggle()
      } label: {
        Image(systemName: revealsValue ? "eye" : "eye.slash")
      }
      .buttonStyle(.plain)
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
      .padding(-10)
      .accessibilityLabel(Text(verbatim: revealAccessibilityLabel))
      .accessibilityIdentifier(revealIdentifier)
      validation()
        .frame(width: 24, height: 24)
    }
    .onChange(of: text) { _, value in
      if value.isEmpty {
        revealsValue = false
      }
    }
  }

  private var revealAccessibilityLabel: String {
    let format = revealsValue
      ? String(localized: "Hide %@")
      : String(localized: "Show %@")
    return String.localizedStringWithFormat(format, name)
  }
}

extension CredentialSecretField where Validation == EmptyView {
  internal init(
    name: String,
    text: Binding<String>,
    revealIdentifier: String,
    @ViewBuilder field: @escaping () -> Field
  ) {
    self.init(
      name: name,
      text: text,
      revealIdentifier: revealIdentifier,
      field: field,
      validation: { EmptyView() }
    )
  }
}
