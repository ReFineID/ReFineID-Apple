#if os(macOS)

  import SwiftUI

  /// The Time-Stamp Authorities pane: the ordered list an archival
  /// signature asks for its timestamps, first answer used.
  ///
  /// The list is the whole interface. Addresses are edited in place,
  /// rows are added and removed with the same +/- controls every Mac
  /// table carries, and the order is changed by dragging - none of
  /// which needs a sentence of instructions. The one thing that does
  /// need words, what the badges mean, is written once in the legend
  /// under the list.
  internal struct TimestampAuthoritiesSettingsView: View {
    /// One row: a stable identity and the address being edited.
    ///
    /// The identity must not be the address itself - rows are edited
    /// in place, and a row whose identity changed with every
    /// keystroke would lose focus after the first one.
    private struct Row: Identifiable, Equatable {
      let id = UUID()
      var address: String
    }

    private static let paneWidth: CGFloat = 520
    private static let listHeight: CGFloat = 160
    private static let rowSpacing: CGFloat = 8
    private static let legendSpacing: CGFloat = 14
    private static let legendSymbolSpacing: CGFloat = 4

    @State private var rows: [Row]
    @State private var selection: UUID?
    @State private var editing: UUID?
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedRow: UUID?

    internal var body: some View {
      Form {
        Section {
          authorityList
          controls
        } footer: {
          legend
        }
        if let editing,
          let row = rows.first(where: { $0.id == editing })
        {
          credentialsSection(for: row.address)
        }
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.paneWidth)
      .onChange(of: rows) { _, _ in persist() }
      .onChange(of: focusedRow) { _, now in
        // Focusing a row is choosing it; a row abandoned empty was
        // never an address.
        if let now { selection = now }
        rows.removeAll { $0.address.isEmpty && $0.id != now }
      }
    }

    /// The ordered authorities, edited in place, dragged into the
    /// order they are asked.
    @ViewBuilder private var authorityList: some View {
      List(selection: $selection) {
        ForEach($rows) { $row in
          authorityRow($row)
        }
        .onMove { source, destination in
          rows.move(fromOffsets: source, toOffset: destination)
        }
        .onDelete { offsets in
          rows.remove(atOffsets: offsets)
        }
      }
      .frame(minHeight: Self.listHeight)
      .onDeleteCommand { removeSelected() }
      .accessibilityLabel("Time-stamp authorities, used in this order")
    }

    /// Add, remove, credentials, and the way back to the shipped set.
    @ViewBuilder private var controls: some View {
      HStack {
        Button {
          addRow()
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help("Add an authority")
        .accessibilityLabel("Add an authority")
        Button {
          removeSelected()
        } label: {
          Image(systemName: "minus")
        }
        .buttonStyle(.borderless)
        .disabled(selection == nil)
        .help("Remove the selected authority")
        .accessibilityLabel("Remove the selected authority")
        Spacer()
        Button("Credentials...") {
          beginEditingCredentials()
        }
        .disabled(selection == nil)
        .help("Some commercial authorities need a username and password")
        Button("Restore Defaults") {
          restoreDefaults()
        }
        .disabled(rows.map(\.address) == TimestampAuthorityStore.defaults)
      }
    }

    /// What each badge means, said once.
    @ViewBuilder private var legend: some View {
      HStack(spacing: Self.legendSpacing) {
        legendEntry(
          symbol: "checkmark.seal.fill",
          style: AnyShapeStyle(.green),
          text: "Qualified for eIDAS use"
        )
        legendEntry(
          symbol: "seal",
          style: AnyShapeStyle(.secondary),
          text: "Not qualified"
        )
        if rows.contains(where: { !Self.isUsable($0.address) }) {
          legendEntry(
            symbol: "exclamationmark.triangle.fill",
            style: AnyShapeStyle(.orange),
            text: "Not a usable address"
          )
        }
      }
      .font(.footnote)
    }

    internal init() {
      _rows = State(
        initialValue: TimestampAuthorityStore.load().map { Row(address: $0) }
      )
    }

    /// Whether the address names a service this app could reach.
    ///
    /// Both schemes are accepted: timestamping is specified over
    /// plain HTTP and several qualified authorities publish exactly
    /// that, so insisting on one scheme would refuse half the
    /// trusted list.
    private static func isUsable(_ address: String) -> Bool {
      guard let url = URL(string: address), let scheme = url.scheme else {
        return false
      }
      return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// One row: its badge, its address, and whether it sends
    /// credentials.
    @ViewBuilder
    private func authorityRow(_ row: Binding<Row>) -> some View {
      HStack(spacing: Self.rowSpacing) {
        badge(for: row.wrappedValue.address)
        TextField("Address", text: row.address)
          .textFieldStyle(.plain)
          .labelsHidden()
          .focused($focusedRow, equals: row.wrappedValue.id)
        if TimestampAuthorityStore.username(for: row.wrappedValue.address) != nil {
          Image(systemName: "person.badge.key.fill")
            .foregroundStyle(.secondary)
            .help("Sends a username and password")
            .accessibilityLabel("has credentials")
        }
      }
    }

    /// What the legend explains, one symbol per row.
    @ViewBuilder
    private func badge(for address: String) -> some View {
      if !Self.isUsable(address) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityLabel("not a usable address")
      } else if TimestampAuthorityStore.isQualified(address) {
        Image(systemName: "checkmark.seal.fill")
          .foregroundStyle(.green)
          .accessibilityLabel("qualified for eIDAS use")
      } else {
        Image(systemName: "seal")
          .foregroundStyle(.secondary)
          .accessibilityLabel("not marked qualified")
      }
    }

    /// One legend item, symbol and meaning.
    @ViewBuilder
    private func legendEntry(
      symbol: String,
      style: AnyShapeStyle,
      text: LocalizedStringKey
    ) -> some View {
      HStack(spacing: Self.legendSymbolSpacing) {
        Image(systemName: symbol)
          .foregroundStyle(style)
        Text(text)
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
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
        TextField("Username", text: $username)
          .textContentType(nil)
        SecureField("Password", text: $password)
        HStack {
          Spacer()
          Button("Done") {
            saveCredentials(for: authority)
          }
        }
      } header: {
        Text(authority)
      }
    }

    /// Appends an empty row and puts the cursor in it.
    private func addRow() {
      let row = Row(address: "")
      rows.append(row)
      selection = row.id
      focusedRow = row.id
    }

    /// Removes the selected row.
    private func removeSelected() {
      guard let selected = selection else { return }
      rows.removeAll { $0.id == selected }
      selection = nil
      if editing == selected {
        editing = nil
      }
    }

    /// Opens the credential fields for the selected authority.
    private func beginEditingCredentials() {
      guard let selected = selection,
        let row = rows.first(where: { $0.id == selected })
      else { return }
      editing = selected
      username = TimestampAuthorityStore.username(for: row.address) ?? ""
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

    /// Saves every non-empty address, in the order shown.
    ///
    /// A row that is not yet a usable address is saved too: it is
    /// wrong visibly, with its warning badge, rather than silently
    /// dropped behind the holder's back.
    private func persist() {
      TimestampAuthorityStore.save(
        rows.map(\.address).filter { !$0.isEmpty }
      )
    }

    /// Back to the shipped authorities.
    private func restoreDefaults() {
      TimestampAuthorityStore.restoreDefaults()
      rows = TimestampAuthorityStore.load().map { Row(address: $0) }
      selection = nil
      editing = nil
    }
  }

#endif
