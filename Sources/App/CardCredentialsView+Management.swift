// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

extension CardCredentialsView {
  internal var managementSection: some View {
    Section {
      NavigationLink {
        CardManagementView()
      } label: {
        Label("Manage card", systemImage: "key")
      }
      .accessibilityIdentifier("manageCard")
    }
  }
}
