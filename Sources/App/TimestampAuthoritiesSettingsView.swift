#if os(macOS)

  import SwiftUI

  /// The Time-Stamp Authorities pane: one table, in the order asked.
  ///
  /// Every cell is edited in place, like a spreadsheet: the address,
  /// the Basic-auth username and password beside it - empty for a
  /// public service - and an open line at the bottom waiting for the
  /// next authority. Each row carries its own delete control, so
  /// nothing depends on a selection, and the badges are explained
  /// once, in the legend underneath.
  internal struct TimestampAuthoritiesSettingsView: View {
    /// One row of the table.
    ///
    /// The identity must not be the address itself - rows are edited
    /// in place, and a row whose identity changed with every
    /// keystroke would lose focus after the first one.
    private struct Row: Identifiable, Equatable {
      let id = UUID()
      var address = ""
      var username = ""
      var password = ""
      var qualified = false

      /// Nothing typed in any cell.
      var isBlank: Bool {
        address.isEmpty && username.isEmpty && password.isEmpty
      }
    }

    private static let paneWidth: CGFloat = 640
    private static let listHeight: CGFloat = 170
    private static let cellSpacing: CGFloat = 8
    private static let badgeWidth: CGFloat = 16
    private static let credentialWidth: CGFloat = 110
    private static let legendSpacing: CGFloat = 14
    private static let legendSymbolSpacing: CGFloat = 4

    /// How long an entry rests before its scheme is asked after.
    private static let typingRestDelay: Duration = .seconds(1)

    @State private var rows: [Row]

    /// What the stores already hold, keyed by row, so a keystroke
    /// writes only the row it changed.
    @State private var saved: [UUID: Row]

    /// The scheme probes in flight, keyed by row, so another
    /// keystroke restarts the row's rest timer.
    @State private var probes: [UUID: Task<Void, Never>] = [:]

    @FocusState private var focusedRow: UUID?

    internal var body: some View {
      Form {
        Section {
          table
          HStack {
            Spacer()
            Button("Restore Defaults") {
              restoreDefaults()
            }
            .disabled(isShippedSet)
          }
        } footer: {
          legend
        }
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.paneWidth)
      .onChange(of: rows) { _, _ in reconcile() }
      .onChange(of: focusedRow) { _, _ in tidy() }
    }

    /// The table itself, dragged into the order the services are
    /// asked.
    @ViewBuilder private var table: some View {
      List {
        columnHeader
        ForEach($rows) { $row in
          tableRow($row)
        }
        .onMove { source, destination in
          rows.move(fromOffsets: source, toOffset: destination)
        }
      }
      .frame(minHeight: Self.listHeight)
      .accessibilityLabel("Time-stamp authorities, used in this order")
    }

    /// The column names, aligned over their cells.
    @ViewBuilder private var columnHeader: some View {
      HStack(spacing: Self.cellSpacing) {
        Spacer().frame(width: Self.badgeWidth)
        Text("Address").frame(maxWidth: .infinity, alignment: .leading)
        Text("Username").frame(width: Self.credentialWidth, alignment: .leading)
        Text("Password").frame(width: Self.credentialWidth, alignment: .leading)
        Spacer().frame(width: Self.badgeWidth)
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }

    /// What each badge means, said once.
    @ViewBuilder private var legend: some View {
      HStack(spacing: Self.legendSpacing) {
        legendEntry(
          "checkmark.seal.fill",
          AnyShapeStyle(.green),
          "Qualified for eIDAS use"
        )
        legendEntry(
          "seal",
          AnyShapeStyle(.secondary),
          "Not qualified - click the seal to mark yours"
        )
        if rows.contains(where: { row in
          !row.address.isEmpty && !AuthoritySchemeResolver.isUsable(row.address)
        }) {
          legendEntry(
            "exclamationmark.triangle.fill",
            AnyShapeStyle(.orange),
            "Not a usable address"
          )
        }
      }
      .font(.footnote)
    }

    /// Whether the table shows exactly the shipped set.
    private var isShippedSet: Bool {
      rows.map(\.address).filter { !$0.isEmpty }
        == TimestampAuthorityStore.defaults
        && rows.allSatisfy { $0.username.isEmpty && $0.password.isEmpty }
    }

    internal init() {
      let loaded = Self.loadedRows()
      _rows = State(initialValue: loaded)
      _saved = State(
        initialValue: Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
      )
    }

    /// The stored authorities as rows, with the open line appended.
    private static func loadedRows() -> [Row] {
      var loaded = TimestampAuthorityStore.load().map { address in
        let credentials = TimestampAuthorityStore.credentials(for: address)
        return Row(
          address: address,
          username: credentials?.username ?? "",
          password: credentials?.password ?? "",
          qualified: TimestampAuthorityStore.isQualified(address)
        )
      }
      loaded.append(Row())
      return loaded
    }

    /// One row: badge, three cells, delete.
    @ViewBuilder
    private func tableRow(_ row: Binding<Row>) -> some View {
      HStack(spacing: Self.cellSpacing) {
        badge(row)
        TextField(
          isOpenLine(row.wrappedValue) ? "Add an authority" : "Address",
          text: row.address
        )
        .textFieldStyle(.plain)
        .focused($focusedRow, equals: row.wrappedValue.id)
        TextField("Username", text: row.username)
          .textFieldStyle(.plain)
          .frame(width: Self.credentialWidth)
          .focused($focusedRow, equals: row.wrappedValue.id)
        SecureField("Password", text: row.password)
          .textFieldStyle(.plain)
          .frame(width: Self.credentialWidth)
          .focused($focusedRow, equals: row.wrappedValue.id)
        deleteControl(row.wrappedValue)
      }
    }

    /// The row's badge.
    ///
    /// The warning for an unusable address, the seal for a usable
    /// one. A shipped authority's seal is a fact and cannot be
    /// clicked off; an added authority's seal is the holder's own
    /// mark, toggled by clicking it, because qualification is a
    /// trusted-list fact the app cannot verify offline.
    @ViewBuilder
    private func badge(_ row: Binding<Row>) -> some View {
      let address = row.wrappedValue.address
      if address.isEmpty {
        Spacer().frame(width: Self.badgeWidth)
      } else if !AuthoritySchemeResolver.isUsable(address) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .frame(width: Self.badgeWidth)
          .accessibilityLabel("not a usable address")
      } else {
        let shipped = TimestampAuthorityStore.defaults.contains(address)
        let qualified = shipped || row.wrappedValue.qualified
        Button {
          row.wrappedValue.qualified.toggle()
        } label: {
          Image(systemName: qualified ? "checkmark.seal.fill" : "seal")
            .foregroundStyle(
              qualified ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)
            )
        }
        .buttonStyle(.borderless)
        .disabled(shipped)
        .frame(width: Self.badgeWidth)
        .help("Whether this service is qualified for eIDAS use")
        .accessibilityLabel(
          qualified ? "qualified for eIDAS use" : "not marked qualified"
        )
        .accessibilityHint("Toggles the qualification mark")
      }
    }

    /// The row's own delete control; the open line has nothing to
    /// delete.
    @ViewBuilder
    private func deleteControl(_ row: Row) -> some View {
      if isOpenLine(row) {
        Spacer().frame(width: Self.badgeWidth)
      } else {
        Button {
          rows.removeAll { $0.id == row.id }
        } label: {
          Image(systemName: "trash")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .frame(width: Self.badgeWidth)
        .help("Remove this authority")
        .accessibilityLabel("Remove \(row.address)")
      }
    }

    /// One legend item, symbol and meaning.
    @ViewBuilder
    private func legendEntry(
      _ symbol: String, _ style: AnyShapeStyle, _ text: LocalizedStringKey
    ) -> some View {
      HStack(spacing: Self.legendSymbolSpacing) {
        Image(systemName: symbol).foregroundStyle(style)
        Text(text).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
    }

    /// The empty row at the bottom, waiting for the next authority.
    private func isOpenLine(_ row: Row) -> Bool { row.isBlank && row.id == rows.last?.id }

    /// A scheme-less entry is completed once typing rests: https is
    /// tried first and preferred, http accepted, and the address is
    /// rewritten only if it has not changed since - and only to a
    /// scheme the service answered on.
    private func scheduleSchemeCompletion() {
      for row in rows
      where !row.address.isEmpty && !row.address.contains("://") {
        probes[row.id]?.cancel()
        let (bare, identity) = (row.address, row.id)
        probes[identity] = Task { @MainActor in
          try? await Task.sleep(for: Self.typingRestDelay)
          guard !Task.isCancelled,
            let completed = await AuthoritySchemeResolver.complete(bare),
            let index = rows.firstIndex(where: { $0.id == identity }),
            rows[index].address == bare
          else { return }
          rows[index].address = completed
        }
      }
    }

    /// Writes what changed and keeps the open line open.
    private func reconcile() {
      tidy()
      scheduleSchemeCompletion()
      TimestampAuthorityStore.save(rows.map(\.address).filter { !$0.isEmpty })
      for row in rows where !row.address.isEmpty && saved[row.id] != row {
        TimestampAuthorityStore.saveCredentials(
          username: row.username, password: row.password, for: row.address
        )
        if !TimestampAuthorityStore.defaults.contains(row.address) {
          TimestampAuthorityStore.setQualified(row.qualified, for: row.address)
        }
      }
      forgetOrphans()
      saved = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    /// An address deleted or renamed away keeps no marks behind.
    private func forgetOrphans() {
      let current = Set(rows.map(\.address))
      for old in saved.values
      where !old.address.isEmpty && !current.contains(old.address) {
        TimestampAuthorityStore.saveCredentials(
          username: "", password: "", for: old.address
        )
        TimestampAuthorityStore.setQualified(false, for: old.address)
      }
    }

    /// A blank row is kept only as the open line at the bottom, or
    /// while the cursor is still in it.
    private func tidy() {
      let lastIdentity = rows.last?.id
      rows.removeAll { row in
        row.isBlank && row.id != lastIdentity && row.id != focusedRow
      }
      if rows.last?.isBlank != true {
        rows.append(Row())
      }
    }

    /// Back to the shipped authorities.
    ///
    /// Only the list itself is reset here: the writes that clear
    /// leftover credentials and marks follow from the list change,
    /// through the same reconciliation every edit takes.
    private func restoreDefaults() {
      TimestampAuthorityStore.restoreDefaults()
      rows = Self.loadedRows()
    }
  }

#endif
