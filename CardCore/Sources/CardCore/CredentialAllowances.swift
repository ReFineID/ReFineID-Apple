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

/// One credential's two allowances, as the card reports them.
public struct CredentialAllowances: Equatable, Sendable {
  /// How many times the credential itself may still be presented
  /// successfully.
  public let usages: CredentialAllowance

  /// How many times it may still unblock something.
  ///
  /// Only meaningful for the PUK, and the number that decides whether
  /// a PUK survives being used.
  public let unblockings: CredentialAllowance

  /// Groups one reading.
  public init(usages: CredentialAllowance, unblockings: CredentialAllowance) {
    self.usages = usages
    self.unblockings = unblockings
  }
}
