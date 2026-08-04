#if os(macOS)

  import SwiftUI

  /// The Time-Stamp Authorities pane: the ordered list an archival
  /// signature asks for its qualified timestamps.
  ///
  /// A list rather than rows with arrow buttons. The order is the whole
  /// point of this pane - the first authority to answer is the one used
  /// - and dragging is how a Mac reorders a list, so the rows carry no
  /// buttons for moving and the list carries the behaviour instead.
  internal struct TimestampAuthoritiesSettingsView: View {
    private static let paneWidth: CGFloat = 520
    private static let listHeight: CGFloat = 160
    private static let rowSpacing: CGFloat = 8

    @State private var authorities = TimestampAuthorityStore.load()
    @State private var newEntry = ""
    @State private var selection: String?
    @State private var editing: String?
    @State private var username = ""
    @State private var password = ""

    /// Whether the entry names a service this app could reach.
    ///
    /// Both schemes are accepted: timestamping is specified over plain
    /// HTTP and many qualified authorities publish exactly that, so
    /// insisting on one scheme would refuse half the trusted list.
    private var isEntryUsable: Bool {
      guard let url = URL(string: newEntry), let scheme = url.scheme else {
        return false
      }
      return (scheme == "http" || scheme == "https") && url.host != nil
    }

    internal var body: some View {
      Form {
        listSection
        editSection
        if let editing {
          credentialsSection(for: editing)
        }
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.paneWidth)
    }

    /// The ordered authorities, dragged into the order they are asked.
    @ViewBuilder private var listSection: some View {
      Section {
        List(selection: $selection) {
          ForEach(authorities, id: \.self) { authority in
            authorityRow(authority)
          }
          .onMove { source, destination in
            authorities.move(fromOffsets: source, toOffset: destination)
            TimestampAuthorityStore.save(authorities)
          }
          .onDelete { offsets in
            authorities.remove(atOffsets: offsets)
            TimestampAuthorityStore.save(authorities)
          }
        }
        .frame(minHeight: Self.listHeight)
        .accessibilityLabel("Time-stamp authorities, in the order asked")
      } header: {
        Text("Asked in this order; the first to answer is used")
      } footer: {
        Text("Drag to reorder. Select one and press Delete to remove it.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }

    /// Adding an authority, and the way back to the shipped set.
    @ViewBuilder private var editSection: some View {
      Section {
        HStack {
          TextField("Address of a time-stamp authority", text: $newEntry)
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
          Button("Credentials...") {
            beginEditingCredentials()
          }
          .disabled(selection == nil)
          .help("Some commercial authorities need a username and password")
          Spacer()
          Button("Restore Defaults") {
            TimestampAuthorityStore.restoreDefaults()
            authorities = TimestampAuthorityStore.load()
            selection = nil
            editing = nil
          }
          .disabled(authorities == TimestampAuthorityStore.defaults)
          .accessibilityIdentifier("timestampAuthorityRestore")
        }
      }
    }

    /// One authority: whether it is qualified, and its address.
    @ViewBuilder
    private func authorityRow(_ authority: String) -> some View {
      HStack(spacing: Self.rowSpacing) {
        qualificationBadge(for: authority)
        Text(authority)
          .lineLimit(1)
          .truncationMode(.middle)
        if TimestampAuthorityStore.username(for: authority) != nil {
          Image(systemName: "person.badge.key.fill")
            .foregroundStyle(.secondary)
            .help("Sends a username and password")
            .accessibilityLabel("has credentials")
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityValue(authority)
    }

    /// The seal saying whether this service is qualified for eIDAS
    /// use; colour underlines it, the symbol and label carry it.
    @ViewBuilder
    private func qualificationBadge(for authority: String) -> some View {
      let qualified = TimestampAuthorityStore.isQualified(authority)
      Image(systemName: qualified ? "checkmark.seal.fill" : "seal")
        .foregroundStyle(
          qualified ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)
        )
        .help(qualified ? "Qualified for eIDAS use" : "Not marked as qualified")
        .accessibilityLabel(
          qualified ? "eIDAS qualified" : "not marked qualified"
        )
    }

    /// Basic-auth entry and the qualification mark for one authority.
    @ViewBuilder
    private func credentialsSection(for authority: String) -> some View {
      Section {
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
          Button("Done") {
            saveCredentials(for: authority)
          }
          .accessibilityIdentifier("timestampAuthoritySaveCredentials")
        }
      } header: {
        Text(authority)
      } footer: {
        Text("Leave the username empty for a public authority.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }

    /// Opens the credential fields for the selected authority.
    private func beginEditingCredentials() {
      guard let authority = selection else { return }
      editing = authority
      username = TimestampAuthorityStore.username(for: authority) ?? ""
      password = ""
    }

    /// Stores what was entered and closes the fields.
    private func saveCredentials(for authority: String) {
      TimestampAuthorityStore.saveCredentials(
        username: username,
        password: password,
        for: authority
      )
      editing = nil
      username = ""
      password = ""
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
