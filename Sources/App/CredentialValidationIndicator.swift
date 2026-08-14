// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// One compact validation result shared by card credential forms.
internal struct CredentialValidationIndicator: View {
  internal let valid: Bool
  internal var entriesDiffer = false
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
    return entriesDiffer ? "exclamationmark.triangle.fill" : "xmark.circle.fill"
  }

  private var color: Color {
    if valid { return .green }
    return entriesDiffer ? .orange : .red
  }

  private var accessibilityDescription: String {
    if valid { return String(localized: "Valid entry") }
    return entriesDiffer
      ? String(localized: "The new entries differ.")
      : String(localized: "Invalid entry")
  }
}
