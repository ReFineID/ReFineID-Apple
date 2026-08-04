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
    private typealias Row = TimestampAuthoritiesModel.Row

    private static let paneWidth: CGFloat = 640
    private static let listHeight: CGFloat = 170
    private static let cellSpacing: CGFloat = 8
    private static let badgeWidth: CGFloat = 16
    private static let credentialWidth: CGFloat = 110
    private static let legendSpacing: CGFloat = 14
    private static let legendSymbolSpacing: CGFloat = 4

    @State private var model = TimestampAuthoritiesModel()
    @FocusState private var focusedRow: UUID?

    internal var body: some View {
      Form {
        Section {
          table
          HStack {
            Spacer()
            Button("Restore Defaults") {
              model.restoreDefaults()
            }
            .disabled(model.isShippedSet)
          }
        } footer: {
          legend
        }
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.paneWidth)
      .onChange(of: model.rows) { _, _ in
        model.reconcile(focused: focusedRow)
      }
      .onChange(of: focusedRow) { _, now in
        model.tidy(keeping: now)
      }
    }

    /// The table itself, dragged into the order the services are
    /// asked.
    @ViewBuilder private var table: some View {
      List {
        columnHeader
        ForEach(Bindable(model).rows) { $row in
          tableRow($row)
        }
        .onMove { source, destination in
          model.rows.move(fromOffsets: source, toOffset: destination)
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
          "Not on the EU trusted lists"
        )
        if model.rows.contains(where: { row in
          row.check == .notTimestampService
        }) {
          legendEntry(
            "xmark.seal.fill",
            AnyShapeStyle(.red),
            "Not a time-stamp service"
          )
        }
        if model.rows.contains(where: { row in
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

    /// One row: badge, three cells, delete.
    @ViewBuilder
    private func tableRow(_ row: Binding<Row>) -> some View {
      HStack(spacing: Self.cellSpacing) {
        badge(row)
        TextField(
          model.isOpenLine(row.wrappedValue) ? "Add an authority" : "Address",
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
    /// The warning for an unusable address, a spinner while the
    /// qualification test runs, the seal once it has spoken. The
    /// seal is a tested fact, not a control: the service proves who
    /// it is by answering a real timestamp request, and the EU
    /// trusted lists say whether that identity is qualified.
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
      } else if model.testing.contains(row.wrappedValue.id) {
        ProgressView()
          .controlSize(.small)
          .frame(width: Self.badgeWidth)
          .accessibilityLabel("testing qualification")
      } else if row.wrappedValue.check == .notTimestampService {
        Image(systemName: "xmark.seal.fill")
          .foregroundStyle(.red)
          .frame(width: Self.badgeWidth)
          .help("Answers, but not with timestamps")
          .accessibilityLabel("not a time-stamp service")
      } else {
        let qualified =
          TimestampAuthorityStore.defaults.contains(address)
          || row.wrappedValue.qualified
        Image(systemName: qualified ? "checkmark.seal.fill" : "seal")
          .foregroundStyle(
            qualified ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)
          )
          .frame(width: Self.badgeWidth)
          .help(
            qualified
              ? "Qualified for eIDAS use" : "Not on the EU trusted lists"
          )
          .accessibilityLabel(
            qualified ? "qualified for eIDAS use" : "not qualified"
          )
      }
    }

    /// The row's own delete control; the open line has nothing to
    /// delete.
    @ViewBuilder
    private func deleteControl(_ row: Row) -> some View {
      if model.isOpenLine(row) {
        Spacer().frame(width: Self.badgeWidth)
      } else {
        Button {
          model.rows.removeAll { $0.id == row.id }
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
        Image(systemName: symbol)
          .foregroundStyle(style)
          .accessibilityHidden(true)
        Text(text).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
    }
  }

#endif
