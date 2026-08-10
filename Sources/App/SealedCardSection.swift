#if os(macOS)

  import CardCore
  import SwiftUI

  /// The entry a sealed contactless card is waiting for: one box per
  /// printed digit.
  ///
  /// Shown only when the slot's answer proves the card is on the
  /// antenna, so it needs no explaining - the card face says CAN over
  /// six digits, and the row shows CAN beside six boxes. The sixth
  /// digit submits on its own: the driver tries a number once, and a
  /// refused number is latched by fingerprint and never re-tried by
  /// itself, so the automatic try spends exactly one of the card's
  /// attempts per number entered. A refusal shakes the row and turns
  /// it red; typing again clears it. The boxes draw what the hidden
  /// field holds, and nothing can be selected or copied back out of
  /// them.
  internal struct SealedCardSection: View {
    /// The sideways nudge a refusal draws.
    private struct Shake: GeometryEffect {
      /// How far the row swings, in points.
      private static let amplitude: CGFloat = 8

      /// Sine phase per refusal, in half-turns: six half-turns is
      /// three full swings.
      private static let halfTurns: CGFloat = 6

      /// Counts refusals; animating to the next integer plays one
      /// shake.
      var animatableData: CGFloat

      func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(
          CGAffineTransform(
            translationX: Self.amplitude
              * sin(animatableData * Self.halfTurns * .pi),
            y: 0))
      }
    }

    private static let boxCount = CardAccessNumber.digitCount
    private static let boxSpacing: CGFloat = 6
    private static let boxWidth: CGFloat = 32
    private static let boxHeight: CGFloat = 40
    private static let boxCorner: CGFloat = 6
    private static let boxBorder: CGFloat = 1

    /// The heavier border on the box the next digit lands in.
    private static let activeBoxBorder: CGFloat = 2

    /// How long a submitted number is watched for its verdict.
    ///
    /// Nonisolated: the watching runs off the main actor. Long,
    /// because the verdict may wait for the holder to present the
    /// card again; the watch ends early with the verdict, and with
    /// this section when the identity publishes.
    nonisolated private static let refusalPolls = 120

    /// Polls after which the row asks for the card again.
    ///
    /// A mint that is going to happen has happened well within this;
    /// past it, the system is not going to look at the card where it
    /// lies, and presenting the card again is what makes it look.
    nonisolated private static let retapPolls = 6

    /// The pause between looks, in milliseconds.
    nonisolated private static let refusalPollMilliseconds = 500

    @State private var number = ""
    @State private var refused = false
    @State private var trying = false
    @State private var retapNeeded = false
    @State private var shakes: CGFloat = 0
    @FocusState private var focused: Bool

    internal var body: some View {
      Section {
        entry
          .modifier(Shake(animatableData: shakes))
      }
    }

    /// The label, the boxes, and the invisible field beneath them.
    ///
    /// The field is the only thing that reads the keyboard or a
    /// paste; the boxes draw its contents. Focus lands on it when
    /// the section appears and returns on any click.
    @ViewBuilder private var entry: some View {
      ZStack {
        TextField("", text: $number)
          .textFieldStyle(.plain)
          .opacity(0)
          .focused($focused)
          .onChange(of: number) { previous, typed in
            react(from: previous, to: typed)
          }
          .accessibilityIdentifier("sealedCardAccessNumber")
        HStack(spacing: Self.boxSpacing) {
          Text(verbatim: "CAN")
            .foregroundStyle(.secondary)
          Spacer()
          // The number is being tried against the card. Leading of
          // the boxes, so their right edge never moves.
          if trying {
            ProgressView()
              .controlSize(.small)
          }
          ForEach(0..<Self.boxCount, id: \.self) { index in
            box(at: index)
          }
        }
      }
      .contentShape(.rect)
      .onTapGesture { focused = true }
      .onAppear { focused = true }
      if retapNeeded {
        // The one thing that makes the system look at the card
        // again: a warm reset is invisible to it, so the number
        // waits until the card arrives.
        Text("Lift the card and lay it back")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }

    /// Takes the offered number back: at launch, and at quit.
    ///
    /// Not when the card leaves. A contactless card leaves the field
    /// between taps, the offer exists to serve the next tap, and
    /// every contactless session - PIN management included - runs
    /// PACE again and needs it. The app run is the offer's lifetime.
    internal static func withdrawOfferedNumber() {
      Task.detached(priority: .utility) {
        CardCredentialStore.withdrawCardAccessNumberFromDriver()
      }
    }

    /// One digit's box: its frame, and the digit once typed.
    ///
    /// The box the next digit lands in carries the accent color -
    /// focus is shown in the accent, never in a verdict color, so
    /// where to type and how it went stay two different signals.
    @ViewBuilder
    private func box(at index: Int) -> some View {
      ZStack {
        RoundedRectangle(cornerRadius: Self.boxCorner)
          .strokeBorder(
            borderStyle(at: index),
            lineWidth: borderWidth(at: index)
          )
          .frame(width: Self.boxWidth, height: Self.boxHeight)
        if let digit = digit(at: index) {
          Text(digit)
            .font(.title3.monospacedDigit())
            .foregroundStyle(
              refused ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
      }
    }

    /// The border for `index`: red when refused, the accent where
    /// the next digit lands, and quiet otherwise.
    private func borderStyle(at index: Int) -> AnyShapeStyle {
      if refused {
        AnyShapeStyle(.red)
      } else if focused, index == number.count {
        AnyShapeStyle(.tint)
      } else {
        AnyShapeStyle(.quaternary)
      }
    }

    /// The border weight for `index`, heavier where the accent is.
    private func borderWidth(at index: Int) -> CGFloat {
      if focused, !refused, index == number.count {
        Self.activeBoxBorder
      } else {
        Self.boxBorder
      }
    }

    /// The typed digit for `index`, once there is one.
    private func digit(at index: Int) -> String? {
      guard index < number.count else { return nil }
      return String(Array(number)[index])
    }

    /// Keeps the entry digits, clears a refusal on any edit, and
    /// submits when the sixth digit lands.
    private func react(from previous: String, to typed: String) {
      let digits = LimitedDigits.cardAccessNumber(typed)
      if digits != typed {
        number = digits
      }
      if refused, digits != previous {
        refused = false
      }
      if digits.count == Self.boxCount, previous.count < Self.boxCount {
        submit(digits)
      } else if digits != previous {
        trying = false
        retapNeeded = false
      }
    }

    /// Offers the number, resets the card so the system asks again,
    /// and watches for the driver's refusal marker.
    ///
    /// The reset is what makes typing enough: without it the system
    /// remembers giving up on the card and nothing re-reads the offer
    /// until the card is physically lifted and laid back. The driver
    /// tries the number once; a refusal shakes this row, and a mint
    /// that succeeds removes the whole section by publishing the
    /// identity.
    ///
    /// Off the main actor: the offer, the reset and the marker are
    /// file and PC/SC calls, which must not block the window.
    private func submit(_ digits: String) {
      trying = true
      retapNeeded = false
      Task.detached(priority: .utility) {
        CardCredentialStore.publishCardAccessNumberToDriver(digits: digits)
        _ = SlotCardReset.resetContactlessCards()
        for poll in 0..<Self.refusalPolls {
          try? await Task.sleep(for: .milliseconds(Self.refusalPollMilliseconds))
          if CardCredentialStore.offeredNumberWasRefused() {
            await MainActor.run {
              trying = false
              retapNeeded = false
              refused = true
              withAnimation { shakes += 1 }
            }
            return
          }
          if poll == Self.retapPolls {
            await MainActor.run {
              trying = false
              retapNeeded = true
            }
          }
        }
      }
    }
  }

#endif
