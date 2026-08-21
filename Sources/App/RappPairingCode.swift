// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CoreImage
  import Foundation
  import SwiftUI

  #if os(iOS)
    import UIKit
  #elseif os(macOS)
    import AppKit
  #endif

  /// Draws a pairing offer as the code the other device scans.
  internal enum RappPairingCode {
    internal static func image(_ value: String) -> Image? {
      let filter = CIFilter(name: "CIQRCodeGenerator")
      filter?.setValue(Data(value.utf8), forKey: "inputMessage")
      // The offer carries a long secret, so every level of recovery costs
      // modules and a denser code is a harder one to scan. The screen is not
      // a printed label: it is clean, lit, and held still, so the lowest
      // level is the one that reads fastest here.
      filter?.setValue("L", forKey: "inputCorrectionLevel")
      guard let output = filter?.outputImage else { return nil }
      #if os(macOS)
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return Image(nsImage: image)
      #else
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
      #endif
    }
  }
#endif
