#if os(macOS)

  /// Signature lengths the card answers with.
  ///
  /// A P-384 signature is the pair (r, s), each the curve's 48-byte
  /// field width. The exact length is sent as the expected response
  /// length: the card is T=0 and a length correction between loading
  /// the hash and asking for the signature can drop the hash, which
  /// would produce a signature over nothing.
  internal enum FineidSignatureLengths {
    /// Bytes in a raw ECDSA P-384 signature.
    internal static let ecdsaP384 = 96
  }

#endif
