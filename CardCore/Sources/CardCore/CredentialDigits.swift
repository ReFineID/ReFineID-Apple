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
/// Shared validation for entered credential digits.
///
/// One implementation of the length-and-character rule, so PIN1, PIN2,
/// and PUK cannot drift apart in what they accept.
internal enum CredentialDigits {
  /// ASCII "0".
  private static let asciiDigitMinimum: UInt8 = 48

  /// ASCII "9".
  private static let asciiDigitMaximum: UInt8 = 57

  /// Validates length and character set, returning a store owning the
  /// digits, or nil for anything that is not `minimumCount` to
  /// `maximumCount` ASCII digits.
  internal static func validated(
    _ digits: String,
    minimumCount: Int,
    maximumCount: Int
  ) -> ZeroizingDigitStore? {
    let bytes = Array(digits.utf8)
    guard
      bytes.count >= minimumCount,
      bytes.count <= maximumCount,
      bytes.allSatisfy({ byte in
        byte >= asciiDigitMinimum && byte <= asciiDigitMaximum
      })
    else {
      return nil
    }
    return ZeroizingDigitStore(bytes: bytes)
  }
}
