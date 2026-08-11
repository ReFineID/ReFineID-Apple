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
/// How many times a credential may still be used before the card
/// stops honouring it at all (FINEID S1 v4.2 §3.15.3 Table 19).
///
/// This is not the retry counter. A retry counter falls when the wrong
/// value is presented and is restored by an unblock; an allowance
/// falls when the RIGHT value is presented, and nothing restores it.
/// A PUK with a limited unblocking allowance is spent by being used,
/// which is what makes the difference between a card whose PUK works
/// once and one whose PUK keeps working.
public enum CredentialAllowance: Equatable, Sendable {
  /// This many uses remain.
  case remaining(UInt8)

  /// The card puts no limit on this count.
  case unlimited

  /// Reads a usage-allowance byte.
  internal static func usage(byte: UInt8) -> Self {
    byte == FineidValues.usageUnlimited ? .unlimited : .remaining(byte)
  }

  /// Reads an unblocking-allowance byte, whose no-limit marker differs
  /// from the usage one.
  internal static func unblocking(byte: UInt8) -> Self {
    byte == FineidValues.unblockingUnlimited ? .unlimited : .remaining(byte)
  }
}
