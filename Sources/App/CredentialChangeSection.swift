// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if os(macOS)

  import CardCore
  import SwiftUI

  /// One PIN's change form: the current value, the new one twice, and
  /// a Change that stays disabled until the entries can possibly be
  /// right.
  ///
  /// Keyboard-first: Return advances from field to field, and on the
  /// last field it submits when the entries are complete.
  internal struct CredentialChangeSection: View {
    /// Which PIN this section changes; only the two PINs change here.
    internal enum Credential {
      case pin1
      case pin2

      /// The on-screen name.
      ///
      /// Written the way the holder's own card documentation writes
      /// it, with the space, and used wherever a field or a button
      /// names the credential it spends.
      internal var name: String {
        switch self {
        case .pin1:
          "PIN 1"
        case .pin2:
          "PIN 2"
        }
      }

      /// The name used in accessibility identifiers, which tests match
      /// exactly and which therefore carries no space.
      internal var identifierName: String {
        name.replacingOccurrences(of: " ", with: "")
      }

      /// The entry bounds of this PIN.
      internal var digitBounds: ClosedRange<Int> {
        switch self {
        case .pin1:
          Pin1.minimumDigitCount...Pin1.maximumDigitCount
        case .pin2:
          Pin2.minimumDigitCount...Pin2.maximumDigitCount
        }
      }
    }

    /// The keyboard path through the section.
    private enum Field {
      case current
      case new
      case repeated
    }

    internal let model: CardManagementModel
    internal let credential: Credential

    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var pending: CredentialOperationConfirmation.Operation?
    @FocusState private var focus: Field?

    /// The role this section changes, as the card names it.
    private var role: CredentialRole {
      switch credential {
      case .pin1:
        .pin1
      case .pin2:
        .pin2
      }
    }

    /// Ready when every entry is inside its bounds and the new value
    /// is typed identically twice.
    private var isComplete: Bool {
      credential.digitBounds.contains(current.count)
        && credential.digitBounds.contains(new.count)
        && new == repeated
    }

    internal var body: some View {
      Section {
        entryRows
        if !new.isEmpty, !repeated.isEmpty, new != repeated {
          Text("The new entries differ.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        HStack {
          Spacer()
          Button("Change \(credential.name)") {
            pending = .change(role)
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(!isComplete || model.working)
          .accessibilityIdentifier("managementChange\(credential.identifierName)")
        }
      }
      // Focus is placed after the window has settled, not as the form
      // appears. Measured: assigning it in `onAppear`, and declaring it
      // with `defaultFocus`, both left every field empty -- typing a
      // PIN a second and a half after the window opened put the digits
      // nowhere, so a keyboard user had to find the first field with a
      // pointer before the keyboard did anything at all.
      .task {
        // A yield past the window becoming key: assigning focus as the
        // form appears, and declaring it with `defaultFocus`, were both
        // measured leaving every field empty, so a PIN typed a second
        // after the window opened went nowhere and the keyboard could
        // not start the operation at all.
        await InitialFieldFocus.settle()
        focus = .current
      }
      .confirmCredentialOperation($pending, report: model.report) { _ in
        change()
      }
    }

    /// The three secret fields, threaded for Return.
    @ViewBuilder private var entryRows: some View {
      SecureField("Current \(credential.name)", text: $current)
        .onChange(of: current) { _, typed in
          current = LimitedDigits.pin(typed)
        }
        .focused($focus, equals: .current)
        .onSubmit { advance(from: .current) }
        .accessibilityIdentifier("managementChange\(credential.identifierName)Current")
      SecureField("New \(credential.name)", text: $new)
        .onChange(of: new) { _, typed in
          new = LimitedDigits.pin(typed)
        }
        .focused($focus, equals: .new)
        .onSubmit { advance(from: .new) }
        .accessibilityIdentifier("managementChange\(credential.identifierName)New")
      SecureField("New \(credential.name) again", text: $repeated)
        .onChange(of: repeated) { _, typed in
          repeated = LimitedDigits.pin(typed)
        }
        .focused($focus, equals: .repeated)
        .onSubmit { advance(from: .repeated) }
        .accessibilityIdentifier("managementChange\(credential.identifierName)Repeat")
    }

    /// Return advances; on the last field it submits when complete.
    private func advance(from field: Field) {
      switch field {
      case .current:
        focus = .new
      case .new:
        focus = .repeated
      case .repeated:
        // Return on the last field asks the same question the button
        // asks; a keyboard path that skipped it would be the fastest
        // way to spend the wrong counter.
        if isComplete {
          pending = .change(role)
        }
      }
    }

    /// Runs the change and clears the fields when the card accepted.
    private func change() {
      guard isComplete, !model.working else { return }
      let currentEntry = current
      let newEntry = new
      Task {
        let accepted =
          switch credential {
          case .pin1:
            await model.changePin1(current: currentEntry, new: newEntry)
          case .pin2:
            await model.changePin2(current: currentEntry, new: newEntry)
          }
        if accepted {
          current = ""
          new = ""
          repeated = ""
          focus = nil
        }
      }
    }
  }

#endif
