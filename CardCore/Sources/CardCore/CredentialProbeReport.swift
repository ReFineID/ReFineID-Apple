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
/// One counter-safe reading of all three credentials.
public struct CredentialProbeReport: Equatable, Sendable {
  /// PIN1 probe outcome (VERIFY probe form).
  public let pin1: RetryProbeOutcome

  /// PIN2 probe outcome (VERIFY probe form).
  public let pin2: RetryProbeOutcome

  /// PUK probe outcome (GET DATA PIN-container form).
  public let puk: RetryProbeOutcome

  /// The typed retry state, available only when all three probes
  /// returned counters.
  ///
  /// This is diagnostic state. Authentication evaluates the fresh PIN1
  /// outcome alone because PIN2 and PUK are not consumed by that operation.
  public var retryState: CredentialRetryState? {
    guard
      case .remaining(let pin1Count) = pin1,
      case .remaining(let pin2Count) = pin2,
      case .remaining(let pukCount) = puk
    else {
      return nil
    }
    return CredentialRetryState(pin1: pin1Count, pin2: pin2Count, puk: pukCount)
  }

  /// Groups one simultaneous probe of the three credentials.
  public init(
    pin1: RetryProbeOutcome,
    pin2: RetryProbeOutcome,
    puk: RetryProbeOutcome
  ) {
    self.pin1 = pin1
    self.pin2 = pin2
    self.puk = puk
  }
}
