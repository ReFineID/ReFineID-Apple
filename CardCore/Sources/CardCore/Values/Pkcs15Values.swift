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
import Foundation

/// The PKCS#15 tags a card's own directories are written in
/// (ISO 7816-15; FINEID S1 v4.2 uses the same encoding).
internal enum Pkcs15Values {
  /// Context tag of the privateKeys entry in EF.ODF, PKCS#15 [0].
  internal static let privateKeysTag: UInt8 = 0xA0

  /// Context tag of the certificates entry in EF.ODF, PKCS#15 [4].
  internal static let certificatesTag: UInt8 = 0xA4

  /// Context tag of an object's type attributes, PKCS#15 [1].
  internal static let typeAttributesTag: UInt8 = 0xA1

  /// Mask and value identifying any context-specific constructed tag,
  /// which is how an object entry of an unnamed class appears.
  internal static let contextTagMask: UInt8 = 0xF0
  internal static let contextTagValue: UInt8 = 0xA0

  /// Universal DER tags the directories use.
  internal static let sequenceTag: UInt8 = 0x30
  internal static let octetStringTag: UInt8 = 0x04
  internal static let integerTag: UInt8 = 0x02
  internal static let utf8StringTag: UInt8 = 0x0C
}
