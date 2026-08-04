#if os(macOS)

  import SwiftUI

  /// The Time-Stamp Authorities pane in Settings: the ordered list an
  /// archival signature asks for its qualified timestamps, editable
  /// and restorable to the shipped set.
  internal struct TimestampAuthoritiesSettingsView: View {
    private static let paneWidth: CGFloat = 520

    @State private var authorities = TimestampAuthorityStore.load()
    @State private var newEntry = ""
    @State private var editingCredentials: String?
    @State private var username = ""
    @State private var password = ""

    /// Whether the entry parses as an HTTP or HTTPS URL.
    private var isEntryUsable: Bool {
      guard let url = URL(string: newEntry), let scheme = url.scheme else {
        return false
      }
      return scheme == "http" || scheme == "https"
    }

    internal var body: some View {
      Form {
        listSection
        editSection
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.paneWidth)
    }

    /// The ordered authorities, first asked first.
    @ViewBuilder private var listSection: some View {
      Section {
        Text(
          "Asked in this order when a signature needs a qualified "
            + "timestamp; the first authority to answer is used."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        ForEach(Array(authorities.enumerated()), id: \.element) { index, authority in
          authorityRow(index: index, authority: authority)
          if editingCredentials == authority {
            credentialRows(for: authority)
          }
        }
      }
    }

    /// Adding an authority, and the way back to the shipped set.
    @ViewBuilder private var editSection: some View {
      Section {
        HStack {
          TextField("https://", text: $newEntry)
            .textContentType(nil)
            .onSubmit { add() }
            .accessibilityIdentifier("timestampAuthorityEntry")
          Button("Add") {
            add()
          }
          .disabled(!isEntryUsable)
          .accessibilityIdentifier("timestampAuthorityAdd")
        }
        HStack {
          Spacer()
          Button("Restore Defaults") {
            TimestampAuthorityStore.restoreDefaults()
            authorities = TimestampAuthorityStore.load()
          }
          .disabled(authorities == TimestampAuthorityStore.defaults)
          .accessibilityIdentifier("timestampAuthorityRestore")
        }
      }
    }

    /// Basic-auth entry for one paid authority; an empty username
    /// clears it back to public.
    @ViewBuilder
    private func credentialRows(for authority: String) -> some View {
      Toggle(
        "Qualified for eIDAS use (on a national trusted list)",
        isOn: Binding(
          get: { TimestampAuthorityStore.isQualified(authority) },
          set: { TimestampAuthorityStore.setQualified($0, for: authority) }
        )
      )
      .disabled(TimestampAuthorityStore.defaults.contains(authority))
      .accessibilityIdentifier("timestampAuthorityQualified")
      TextField("Username", text: $username)
        .textContentType(nil)
        .accessibilityIdentifier("timestampAuthorityUsername")
      SecureField("Password", text: $password)
        .accessibilityIdentifier("timestampAuthorityPassword")
      HStack {
        Spacer()
        Button("Save Credentials") {
          TimestampAuthorityStore.saveCredentials(
            username: username,
            password: password,
            for: authority
          )
          editingCredentials = nil
          username = ""
          password = ""
        }
        .accessibilityIdentifier("timestampAuthoritySaveCredentials")
      }
    }

    /// One authority: its place, its URL, and the two things a list
    /// needs - move up and remove.
    @ViewBuilder
    private func authorityRow(index: Int, authority: String) -> some View {
      HStack {
        qualificationBadge(for: authority)
        Text(authority)
          .textSelection(.enabled)
        Spacer()
        Button("Basic authentication", systemImage: "person.badge.key") {
          if editingCredentials == authority {
            editingCredentials = nil
          } else {
            editingCredentials = authority
            username = TimestampAuthorityStore.username(for: authority) ?? ""
            password = ""
          }
        }
        .labelStyle(.iconOnly)
        .help("Credentials for a paid authority; leave empty for none")
        Button("Move up", systemImage: "arrow.up") {
          authorities.swapAt(index, index - 1)
          TimestampAuthorityStore.save(authorities)
        }
        .labelStyle(.iconOnly)
        .disabled(index == 0)
        .help("Ask this authority earlier")
        Button("Remove", systemImage: "minus.circle") {
          authorities.remove(at: index)
          TimestampAuthorityStore.save(authorities)
        }
        .labelStyle(.iconOnly)
        .help("Remove this authority")
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Authority \(index + 1)")
      .accessibilityValue(authority)
    }

    /// The seal saying whether this service is qualified for eIDAS
    /// use; color underlines it, the symbol and label carry it.
    @ViewBuilder
    private func qualificationBadge(for authority: String) -> some View {
      let qualified = TimestampAuthorityStore.isQualified(authority)
      Image(systemName: qualified ? "checkmark.seal.fill" : "seal")
        .foregroundStyle(
          qualified ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)
        )
        .help(
          qualified ? "Qualified for eIDAS use" : "Not marked as qualified"
        )
        .accessibilityLabel(
          qualified ? "eIDAS qualified" : "not marked qualified"
        )
    }

    /// Appends a checked entry and persists the list.
    private func add() {
      guard isEntryUsable, !authorities.contains(newEntry) else { return }
      authorities.append(newEntry)
      TimestampAuthorityStore.save(authorities)
      newEntry = ""
    }
  }

#endif
