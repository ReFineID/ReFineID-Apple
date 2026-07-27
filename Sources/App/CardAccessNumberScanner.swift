#if os(iOS)

  import CardCore
  import SwiftUI
  import VisionKit

  /// Reads the six printed digits off the card with the camera.
  ///
  /// Typing six digits off a card held in the other hand is the kind of
  /// small friction that makes setup feel like work, so the camera does
  /// it instead. Nothing is kept here: the scanner hands back digits and
  /// the caller decides what to do with them.
  internal struct CardAccessNumberScanner: UIViewControllerRepresentable {
    /// Watches recognized text for something shaped like an access
    /// number.
    internal final class Coordinator: NSObject, DataScannerViewControllerDelegate {
      private let onRecognize: (String) -> Void
      private var hasRecognized = false

      internal init(onRecognize: @escaping (String) -> Void) {
        self.onRecognize = onRecognize
      }

      /// The first exactly-six-digit run in a line of recognized text.
      ///
      /// Bounded on both sides, so a longer number such as a document
      /// number cannot be mistaken for an access number.
      private static func sixDigitRun(in transcript: String) -> String? {
        var run = ""
        var candidates: [String] = []
        for character in transcript + " " {
          if character.isNumber {
            run.append(character)
            continue
          }
          if run.count == CardAccessNumber.digitCount {
            candidates.append(run)
          }
          run = ""
        }
        return candidates.first
      }

      internal func dataScanner(
        _: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems _: [RecognizedItem]
      ) {
        report(addedItems)
      }

      internal func dataScanner(
        _: DataScannerViewController,
        didUpdate updatedItems: [RecognizedItem],
        allItems _: [RecognizedItem]
      ) {
        report(updatedItems)
      }

      /// Hands back the first six-digit run seen, once.
      ///
      /// The camera keeps recognizing while it is open, so without the
      /// latch the field would be rewritten under the holder's fingers.
      private func report(_ items: [RecognizedItem]) {
        guard !hasRecognized else { return }
        for item in items {
          guard case .text(let text) = item,
            let digits = Self.sixDigitRun(in: text.transcript)
          else {
            continue
          }
          hasRecognized = true
          onRecognize(digits)
          return
        }
      }
    }

    /// Whether this device can scan at all.
    ///
    /// Older hardware and the simulator cannot, and a scan button that
    /// does nothing is worse than no button, so the caller hides it.
    internal static var isAvailable: Bool {
      DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// Called with the first six-digit run the camera recognizes.
    internal let onRecognize: (String) -> Void

    internal func makeCoordinator() -> Coordinator {
      Coordinator(onRecognize: onRecognize)
    }

    internal func makeUIViewController(context: Context) -> DataScannerViewController {
      let scanner = DataScannerViewController(
        recognizedDataTypes: [.text()],
        qualityLevel: .accurate,
        recognizesMultipleItems: false,
        isHighFrameRateTrackingEnabled: false,
        isHighlightingEnabled: true)
      scanner.delegate = context.coordinator
      try? scanner.startScanning()
      return scanner
    }

    internal func updateUIViewController(
      _: DataScannerViewController, context _: Context
    ) {
      // The scanner has no state SwiftUI drives; it reports and closes.
    }
  }

#endif
