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

/// Backing storage for credential digits, overwritten with zeros when the
/// last owner releases it.
///
/// Zeroization in Swift is best effort: copies made before the value reached
/// this store - for example the String the system PIN sheet delivered - are
/// outside its reach. What this store guarantees is that the digits it owns
/// do not outlive their use.
///
/// `@unchecked Sendable` is sound: `bytes` is set once at init (before the
/// store is shared) and mutated only in `deinit` (no concurrent access at
/// that point); every owner is either a noncopyable value with unique
/// ownership (`Pin1`, `Pin1Transmission`) or holds it behind a mutex
/// (`AcceptedPin1Memory`), so it is never mutated while shared.
internal final class ZeroizingDigitStore: @unchecked Sendable {
  /// The raw digit bytes.
  ///
  /// Internal so only the module's own boundary code (fingerprinting, the
  /// future transport) can read them; this class is the sanctioned
  /// bytes-to-type boundary in the lint exception register.
  internal private(set) var bytes: [UInt8]

  internal init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  deinit {
    for index in bytes.indices {
      bytes[index] = 0
    }
  }
}
