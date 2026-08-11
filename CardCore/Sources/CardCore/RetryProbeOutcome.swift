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
/// Outcome of a counter-safe retry probe, after the reference
/// implementation's classification.
///
/// Both probe forms are explicitly side-effect-free:
/// no retry or usage counter changes.
public enum RetryProbeOutcome: Equatable, Sendable {
  /// `6984`: the referenced credential data is invalidated.
  case invalidated

  /// `6983`: the credential is blocked; issuer recovery is the only
  /// path.
  case locked

  /// The card answered without a usable counter (`6300`, or an
  /// attributes object without one).
  case noInformation

  /// Any other status word, preserved for diagnostics.
  case other(UInt16)

  /// The counter: this many attempts remain.
  case remaining(RetryCount)

  /// `9000`: the credential is already verified in this session; the
  /// card reports no counter.
  case verified
}
