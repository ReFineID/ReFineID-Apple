//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
/// Byte values that identify an image encoding.
internal enum ImageValues {
  /// JP2 signature-box length.
  private static let jpeg2000BoxLength: UInt8 = 0x0C

  /// Carriage return in the fixed JP2 signature.
  private static let carriageReturn: UInt8 = 0x0D

  /// Line feed in the fixed JP2 signature.
  private static let lineFeed: UInt8 = 0x0A

  /// The non-ASCII check byte in the fixed JP2 signature.
  private static let jpeg2000Check: UInt8 = 0x87

  /// A zero byte used by the JP2 box length.
  private static let zero: UInt8 = 0

  /// Every JPEG marker opens with this byte (ITU-T T.81 B.1.1.3).
  internal static let markerIntroducer: UInt8 = 0xFF

  /// The start-of-image marker's own byte.
  internal static let startOfImage: UInt8 = 0xD8

  /// ISO/IEC 15444-1 JP2 signature box.
  internal static let jpeg2000Signature =
    [zero, zero, zero, jpeg2000BoxLength]
    + Array("jP  ".utf8)
    + [carriageReturn, lineFeed, jpeg2000Check, lineFeed]
}
