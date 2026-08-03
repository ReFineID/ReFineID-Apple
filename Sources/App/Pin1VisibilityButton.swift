import SwiftUI

/// Reveals or conceals a PIN the holder is still typing.
///
/// The icon names the action rather than the state, which is Apple's
/// convention and the readable one: an eye offers to show a concealed
/// PIN, a struck-through eye offers to hide a revealed one. A closed eye
/// on a concealed field would be an offer to conceal what is already
/// concealed.
///
/// Disabled while there is nothing typed, because there is nothing to
/// reveal: a stored PIN is never read back into this field.
internal struct Pin1VisibilityButton: View {
  /// Whether the PIN is currently shown.
  @Binding internal var isRevealed: Bool

  /// Whether anything has been typed to reveal.
  internal let hasEntry: Bool

  /// Returns the caret to the field, so revealing does not cost the
  /// holder their place in a number they are half way through.
  internal let focusField: () -> Void

  internal var body: some View {
    Button {
      isRevealed.toggle()
      focusField()
    } label: {
      Label(
        isRevealed ? "Hide PIN1" : "Show PIN1",
        systemImage: isRevealed ? "eye.slash" : "eye"
      )
      .labelStyle(.iconOnly)
    }
    .buttonStyle(.borderless)
    .disabled(!hasEntry)
    .accessibilityIdentifier("pin1Visibility")
  }
}
