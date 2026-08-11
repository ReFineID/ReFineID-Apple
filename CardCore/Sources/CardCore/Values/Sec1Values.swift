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

/// The dedicated home for SEC1 elliptic-curve point encoding values.
///
/// Source: SEC 1 v2.0 section 2.3.3, "Elliptic-Curve-Point-to-Octet-String
/// Conversion". Only the uncompressed form is used: the FINEID card and the
/// PACE protocol exchange public points as `04 || X || Y`.
internal enum Sec1Values {
  /// The leading octet marking an uncompressed point, `04 || X || Y`.
  internal static let uncompressedPointTag: UInt8 = 0x04
}
