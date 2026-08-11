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
import CardCore

/// Process-lifetime credential memory shared across token sessions.
///
/// A PIN the card rejected must not be resent for the extension's
/// lifetime, and token sessions come and go across card reinserts, so
/// this state lives at process scope (release plan section 4.3). It
/// holds only non-reversible fingerprints, never a PIN.
internal enum CredentialMemory {
  internal static let rejectedPins = RejectedPinMemory()

  /// Card-bound PIN1 values accepted during this process lifetime.
  ///
  /// In-memory, zeroized, never persisted.
  internal static let acceptedPin1 = AcceptedPin1Memory()
}
