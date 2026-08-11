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
import CCryptoki
import Foundation

/// The DER reading and writing the bridge needs.
///
/// Enough of ASN.1 to move between the structures Security.framework
/// hands out and the attribute and signature encodings PKCS#11 defines:
/// tags, definite lengths in short and long form, and INTEGER content.
/// Named tag values come from EcEncoding.h in the CCryptoki target.
package enum Asn1 {
  /// Base of one DER length octet.
  private static let octetBase = 256

  /// Long-form lengths beyond two octets never occur in the structures
  /// the bridge reads and are rejected.
  private static let maximumLengthOctets = 2

  /// Reads the next tag octet, or nil at the end of input.
  package static func tag(_ bytes: Data, _ index: inout Int) -> CK_BYTE? {
    guard index < bytes.count else { return nil }
    defer { index += 1 }
    return bytes[bytes.startIndex + index]
  }

  /// Reads definite length octets, short or long form.
  package static func length(_ bytes: Data, _ index: inout Int) -> Int? {
    guard let first = tag(bytes, &index) else { return nil }
    guard first & Asn1LongFormLengthFlag != 0 else { return Int(first) }
    let octetCount = Int(first & ~Asn1LongFormLengthFlag)
    guard octetCount > 0, octetCount <= maximumLengthOctets else { return nil }
    var value = 0
    for _ in 0..<octetCount {
      guard let octet = tag(bytes, &index) else { return nil }
      value = value * octetBase + Int(octet)
    }
    return value
  }

  /// Reads an INTEGER and returns its content with leading zero octets
  /// removed, which is how PKCS#11 carries unsigned values.
  package static func integer(_ bytes: Data, _ index: inout Int) -> Data? {
    guard tag(bytes, &index) == Asn1IntegerTag,
      let contentLength = length(bytes, &index),
      contentLength > 0,
      index + contentLength <= bytes.count
    else { return nil }
    let start = bytes.startIndex + index
    var content = bytes[start..<(start + contentLength)]
    index += contentLength
    while content.count > 1, content.first == 0 {
      content = content.dropFirst()
    }
    return Data(content)
  }

  /// The definite length octets encoding a content length.
  package static func lengthOctets(_ count: Int) -> Data {
    let longFormThreshold = Int(Asn1LongFormLengthFlag)
    guard count >= longFormThreshold else { return Data([CK_BYTE(count)]) }
    var bigEndian: [CK_BYTE] = []
    var remaining = count
    while remaining > 0 {
      bigEndian.insert(CK_BYTE(remaining % octetBase), at: 0)
      remaining /= octetBase
    }
    return Data([Asn1LongFormLengthFlag | CK_BYTE(bigEndian.count)]) + bigEndian
  }
}
