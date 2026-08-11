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

/// A PIN1 in transit to the card, usable for one command only.
///
/// The only way to obtain this value is consuming a `Pin1`; the only code
/// that may read it is the module's own transport boundary when it builds
/// the single VERIFY command. It is noncopyable for the same reason its
/// source is: transmit-once is a compile-time property.
public struct Pin1Transmission: ~Copyable {
  /// The digits, still owned by the zeroizing store.
  internal let store: ZeroizingDigitStore
}
