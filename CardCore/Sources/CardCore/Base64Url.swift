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

import Foundation

/// Base64url without padding, the JOSE segment encoding (RFC 7515
/// section 2).
public enum Base64Url {
  /// Encodes without padding.
  public static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// Decodes, restoring padding; nil when the input is not
  /// base64url.
  public static func decode(_ text: String) -> Data? {
    var base64 =
      text
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let block = 4
    let remainder = base64.count % block
    if remainder > 0 {
      base64 += String(repeating: "=", count: block - remainder)
    }
    return Data(base64Encoded: base64)
  }
}
