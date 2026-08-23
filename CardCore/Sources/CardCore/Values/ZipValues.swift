// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The ZIP structural values the ASiC-E container writer emits.
///
/// From the PKWARE APPNOTE, held to the ISO/IEC 21320-1 profile:
/// stored entries only, one volume, no encryption.
internal enum ZipValues {
  /// Local file header signature, `PK\x03\x04` little-endian
  /// (APPNOTE 4.3.7).
  internal static let localHeaderSignature: UInt32 = 0x0403_4B50

  /// Central directory file header signature, `PK\x01\x02`
  /// (APPNOTE 4.3.12).
  internal static let centralHeaderSignature: UInt32 = 0x0201_4B50

  /// End of central directory signature, `PK\x05\x06` (APPNOTE 4.3.16).
  internal static let endOfDirectorySignature: UInt32 = 0x0605_4B50

  /// Minimum version needed to extract: 2.0, meaning stored or deflated
  /// (APPNOTE 4.4.3.2).
  internal static let versionNeeded: UInt16 = 20

  /// Compression method 0: stored (APPNOTE 4.4.5).
  internal static let methodStored: UInt16 = 0

  /// General-purpose bit 11: the entry name is UTF-8 (APPNOTE 4.4.4).
  internal static let utf8NameFlag: UInt16 = 0x0800

  /// CRC-32 polynomial in reflected form (IEEE 802.3, APPNOTE 4.4.7).
  internal static let crcPolynomial: UInt32 = 0xEDB8_8320

  /// Bits per input byte in the bitwise CRC computation.
  internal static let crcBitsPerByte = 8

  /// Local file header length before the entry name begins.
  ///
  /// A reader identifies an ASiC container by looking exactly past
  /// here.
  internal static let localHeaderLength = 30
}
