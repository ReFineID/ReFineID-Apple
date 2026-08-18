// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CoreImage
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import UIKit
  import VisionKit
#elseif os(macOS)
  import AppKit
#endif

#if os(iOS)
  internal struct RappOfferScanner: UIViewControllerRepresentable {
    let onScan: @MainActor @Sendable (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
      let scanner = DataScannerViewController(
        recognizedDataTypes: [.barcode(symbologies: [.qr])],
        qualityLevel: .balanced,
        recognizesMultipleItems: false,
        isHighFrameRateTrackingEnabled: false,
        isPinchToZoomEnabled: true,
        isGuidanceEnabled: true,
        isHighlightingEnabled: true
      )
      scanner.delegate = context.coordinator
      DispatchQueue.main.async { try? scanner.startScanning() }
      return scanner
    }

    func updateUIViewController(
      _: DataScannerViewController,
      context _: Context
    ) {}

    static func dismantleUIViewController(
      _ scanner: DataScannerViewController,
      coordinator _: Coordinator
    ) {
      scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
      private let onScan: @MainActor @Sendable (String) -> Void
      private var accepted = false

      init(onScan: @escaping @MainActor @Sendable (String) -> Void) {
        self.onScan = onScan
      }

      func dataScanner(
        _: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems _: [RecognizedItem]
      ) {
        guard !accepted else { return }
        for item in addedItems {
          guard case .barcode(let barcode) = item,
            let value = barcode.payloadStringValue
          else { continue }
          accepted = true
          Task { @MainActor [onScan] in onScan(value) }
          return
        }
      }
    }
  }
#endif
