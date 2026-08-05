#if os(macOS)

  /// Extends the QR's mixed dot resolution beyond its encoded cells.
  extension StampRenderer {
    /// The published SplitMix64 increment and avalanche multipliers.
    private static let portraitPatternSeed: UInt64 = 11_400_714_819_323_198_485
    private static let portraitPatternRowMix: UInt64 = 13_787_848_793_156_543_929
    private static let portraitPatternColumnMix: UInt64 = 10_723_151_780_598_845_931
    private static let portraitPatternFirstShift: UInt64 = 30
    private static let portraitPatternSecondShift: UInt64 = 27
    private static let portraitPatternFinalShift: UInt64 = 31
    private static let portraitPatternBucketCount: UInt64 = 10
    private static let portraitPatternCentralDotBuckets: UInt64 = 4

    /// A stable choice between one central and four small dots.
    internal static func portraitExtensionUsesCentralDot(
      row: Int,
      column: Int
    ) -> Bool {
      var pattern = Self.portraitPatternSeed
      pattern ^= UInt64(row) &* Self.portraitPatternRowMix
      pattern ^= UInt64(column) &* Self.portraitPatternColumnMix
      pattern ^= pattern >> Self.portraitPatternFirstShift
      pattern &*= Self.portraitPatternRowMix
      pattern ^= pattern >> Self.portraitPatternSecondShift
      pattern &*= Self.portraitPatternColumnMix
      pattern ^= pattern >> Self.portraitPatternFinalShift
      return
        pattern % Self.portraitPatternBucketCount
        < Self.portraitPatternCentralDotBuckets
    }
  }

#endif
