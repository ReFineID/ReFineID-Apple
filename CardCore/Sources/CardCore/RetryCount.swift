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
/// Attempts remaining for one credential, as read side-effect-free from the
/// card.
///
/// Raw bytes exist only at parser boundaries;
/// everything downstream works with refined values like this one.
public struct RetryCount: Equatable, Sendable {
  /// Supported cards encode a retry counter in a single low nibble.
  ///
  /// A value above this is a parser or transport fault, never a real
  /// counter, so construction refuses it instead of letting it into the
  /// domain.
  public static let maximumPlausible: UInt8 = 15

  /// The full retry allowance of an untouched credential on supported
  /// cards: five attempts.
  public static let pristineAllowance: UInt8 = 5

  /// The validated number of attempts remaining.
  public let attemptsRemaining: UInt8

  /// True when this credential retains its full allowance.
  public var isPristine: Bool {
    attemptsRemaining == Self.pristineAllowance
  }

  /// Zero attempts remaining: the credential is blocked.
  public var isBlocked: Bool {
    attemptsRemaining == 0
  }

  /// Refuses any value above `maximumPlausible`.
  public init?(attemptsRemaining: UInt8) {
    guard attemptsRemaining <= Self.maximumPlausible else { return nil }
    self.attemptsRemaining = attemptsRemaining
  }
}
